"""FastAPI backend for the local tennis-forehand form coach.

Everything (pose inference, biomechanics, scoring) runs on-device -- no
network calls are made for inference. See docs/PROTOCOL.md for the wire
contract this server implements.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
import sys
import tempfile
import threading
import time
from collections import deque
from typing import Optional

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

import biomechanics as bio
import scoring
from cameras import center_stage_enabled, list_cameras, open_source
from coach import Coach, load_env as load_coach_env
from pose_engine import PoseEngine
from swing_detector import SwingDetector

VERSION = "1"
DEFAULT_MODEL = "lite"
BLACK_FRAME_MEAN = 4.0
BLACK_FRAME_SECONDS = 2.0
_UNUSED_MAX_CAMERA_PROBE = 4

load_coach_env()

app = FastAPI(title="Tennis Form Coach Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

_latest_frame_lock = threading.Lock()
_latest_frame_jpeg: Optional[bytes] = None

# Pose connections drawn for keyframe skeletons (subset covering torso/limbs).
_SKELETON_EDGES = [
    (11, 12), (11, 23), (12, 24), (23, 24),
    (11, 13), (13, 15), (15, 17), (15, 19), (15, 21),
    (12, 14), (14, 16), (16, 18), (16, 20), (16, 22),
    (23, 25), (25, 27), (27, 29), (27, 31),
    (24, 26), (26, 28), (28, 30), (28, 32),
]


def _draw_skeleton(frame_bgr: np.ndarray, landmarks: list) -> np.ndarray:
    out = frame_bgr.copy()
    h, w = out.shape[:2]
    pts = [(int(p[0] * w), int(p[1] * h)) for p in landmarks]
    for a, b in _SKELETON_EDGES:
        if a < len(pts) and b < len(pts):
            cv2.line(out, pts[a], pts[b], (0, 255, 120), 2, cv2.LINE_AA)
    for x, y in pts:
        cv2.circle(out, (x, y), 3, (0, 140, 255), -1, cv2.LINE_AA)
    return out


def _encode_jpeg_b64(frame_bgr: np.ndarray, quality: int = 80) -> Optional[str]:
    ok, buf = cv2.imencode(".jpg", frame_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
    if not ok:
        return None
    return base64.b64encode(buf.tobytes()).decode("ascii")


def _open_capture(source, aspect: str = "4:3") -> cv2.VideoCapture:
    return open_source(source, aspect=aspect)


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {"ok": True, "model": DEFAULT_MODEL, "version": VERSION}


@app.get("/cameras")
def cameras():
    return {"cameras": list_cameras()}


@app.get("/frame.jpg")
def frame_jpg():
    with _latest_frame_lock:
        data = _latest_frame_jpeg
    if data is None:
        return JSONResponse(status_code=404, content={"error": "no live frame available"})
    return Response(content=data, media_type="image/jpeg")


@app.post("/analyze")
async def analyze(file: UploadFile = File(...), handedness: str = Form("auto"), model: str = Form("lite")):
    suffix = os.path.splitext(file.filename or "upload.mp4")[1] or ".mp4"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        result = _analyze_video(tmp_path, handedness=handedness, model_name=model)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    return JSONResponse(content=result)


def _analyze_video(path: str, handedness: str, model_name: str) -> dict:
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        return {"error": f"could not open video file"}

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    if fps <= 0:
        fps = 30.0

    engine = PoseEngine(model=model_name)
    computer = bio.LiveMetricsComputer(handedness=handedness)
    detector = SwingDetector()

    swings = []
    keyframes = {}
    frame_idx = 0
    duration = 0.0

    try:
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            t = frame_idx / fps
            duration = t
            rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            ts_ms = int(t * 1000)
            landmarks, world_landmarks = engine.detect(rgb, ts_ms)
            metrics = computer.update(landmarks, t)
            phase, report = detector.update(t, landmarks, world_landmarks, metrics)
            if report is not None:
                swings.append(report)
                contact_frame = frame_bgr
                contact_landmarks = None
                for f in detector.buffer:
                    if abs(f["t"] - report["t_contact"]) < 1e-6:
                        contact_landmarks = f["landmarks"]
                        break
                if contact_landmarks is not None:
                    contact_frame = _draw_skeleton(frame_bgr, contact_landmarks)
                b64 = _encode_jpeg_b64(contact_frame, quality=85)
                if b64:
                    keyframes[str(report["id"])] = b64
            frame_idx += 1
    finally:
        cap.release()
        engine.close()

    summary = _build_summary(swings)

    return {
        "duration": round(duration, 3),
        "fps": round(fps, 3),
        "handedness": computer.handedness,
        "swing_count": len(swings),
        "swings": swings,
        "summary": summary,
        "keyframes": keyframes,
    }


def _build_summary(swings: list[dict]) -> dict:
    if not swings:
        return {
            "avg_efficiency": 0,
            "avg_injury_risk": 0,
            "risk_by_joint": {"elbow": 0, "shoulder": 0, "wrist": 0, "lower_back": 0, "knee": 0},
            "force_distribution": {"legs": 0, "hips": 0, "trunk": 0, "shoulder": 0, "arm": 0},
            "top_feedback": [],
        }
    avg_efficiency = round(sum(s["efficiency_score"] for s in swings) / len(swings))
    avg_injury_risk = round(sum(s["injury_risk_score"] for s in swings) / len(swings))

    joint_keys = ["elbow", "shoulder", "wrist", "lower_back", "knee"]
    risk_by_joint = {
        k: round(sum(s["risk_by_joint"].get(k, 0) for s in swings) / len(swings)) for k in joint_keys
    }
    dist_keys = ["legs", "hips", "trunk", "shoulder", "arm"]
    force_distribution = {
        k: round(sum(s["force_distribution"].get(k, 0) for s in swings) / len(swings)) for k in dist_keys
    }
    diff = 100 - sum(force_distribution.values())
    if diff != 0:
        biggest = max(force_distribution, key=force_distribution.get)
        force_distribution[biggest] += diff

    severity_rank = {"danger": 2, "warn": 1, "good": 0}
    seen_titles = set()
    top_feedback = []
    all_items = [item for s in swings for item in s["feedback"]]
    all_items.sort(key=lambda it: severity_rank.get(it["severity"], 0), reverse=True)
    for item in all_items:
        if item["title"] in seen_titles:
            continue
        seen_titles.add(item["title"])
        top_feedback.append(item)
        if len(top_feedback) >= 5:
            break

    return {
        "avg_efficiency": avg_efficiency,
        "avg_injury_risk": avg_injury_risk,
        "risk_by_joint": risk_by_joint,
        "force_distribution": force_distribution,
        "top_feedback": top_feedback,
    }


# ---------------------------------------------------------------------------
# Live websocket
# ---------------------------------------------------------------------------

class LiveSession:
    def __init__(self, camera, model: str, handedness: str, fps: int, jpeg_quality: int, width: int,
                 aspect: str = "4:3", coach: bool = True, coach_voice: bool = True):
        self.camera = camera
        self.aspect = aspect
        self.model = model
        self.fps = max(1, fps)
        self.jpeg_quality = jpeg_quality
        self.width = width

        self.lock = threading.Lock()
        self.latest_frame: Optional[dict] = None
        self.pending_swings: list = []
        self.status_queue: "list[dict]" = []
        self.status_lock = threading.Lock()

        self.computer = bio.LiveMetricsComputer(handedness=handedness)
        self.detector = SwingDetector()

        # The coach runs on its own thread and pushes its messages into the same
        # queue as status updates, so they reach the client in order.
        self.coach = Coach(on_result=self._push_status, speak=coach_voice) if coach else None

        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self.coach:
            self.coach.stop()
        # A session can be stopped before it was ever started (an early client
        # disconnect, or a rejected connection), and joining an unstarted thread
        # raises rather than being a no-op.
        if self._thread.is_alive():
            self._thread.join(timeout=2.0)

    def set_handedness(self, mode: str):
        try:
            self.computer.set_handedness(mode)
        except ValueError:
            pass

    def reset(self):
        self.detector.reset()
        self.computer.reset()

    def _push_status(self, msg: dict):
        with self.status_lock:
            self.status_queue.append(msg)

    def pop_status(self) -> list:
        with self.status_lock:
            out = self.status_queue[:]
            self.status_queue.clear()
        return out

    def pop_swings(self) -> list:
        with self.lock:
            out = self.pending_swings[:]
            self.pending_swings.clear()
        return out

    def get_latest_frame(self) -> Optional[dict]:
        with self.lock:
            return self.latest_frame

    def _run(self):
        global _latest_frame_jpeg
        try:
            engine = PoseEngine(model=self.model)
        except Exception as e:
            self._push_status({"type": "error", "message": f"Failed to load pose model '{self.model}': {e}"})
            return

        cap = _open_capture(self.camera, aspect=self.aspect)
        if not cap.isOpened():
            self._push_status({"type": "error", "message": f"Could not open camera source '{self.camera}'"})
            cap.release()
            engine.close()
            return

        cap_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        cap_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        self._push_status({
            "type": "status", "message": f"Camera opened ({cap_w}x{cap_h})",
            "model": self.model, "handedness": self.computer.handedness_mode, "camera": str(self.camera),
        })
        if center_stage_enabled():
            self._push_status({"type": "status", "message": (
                "Center Stage is on. It pans and crops the image, which distorts "
                "speed and angle measurements. Turn it off in Control Centre > Video Effects.")})

        t0 = time.monotonic()
        black_since = None
        black_warned = False
        recent_frame_times: deque = deque(maxlen=20)
        min_interval = 1.0 / self.fps
        last_emit = 0.0

        try:
            while not self._stop.is_set():
                ok, frame_bgr = cap.read()
                if not ok:
                    time.sleep(0.01)
                    continue

                now = time.monotonic() - t0
                recent_frame_times.append(now)

                # Black-frame watchdog: Continuity Camera iPhones deliver black frames
                # while asleep / face-down; tell the user instead of silently showing nothing.
                if frame_bgr[::16, ::16].mean() < BLACK_FRAME_MEAN:
                    black_since = black_since if black_since is not None else now
                    if not black_warned and now - black_since > BLACK_FRAME_SECONDS:
                        black_warned = True
                        self._push_status({"type": "status", "message": (
                            "Camera is sending black frames. If this is an iPhone: unlock it, "
                            "hold it in landscape near the Mac, and check Settings > General > "
                            "AirPlay & Continuity > Continuity Camera is on.")})
                else:
                    if black_warned:
                        self._push_status({"type": "status", "message": "Camera image restored"})
                    black_since, black_warned = None, False

                h0, w0 = frame_bgr.shape[:2]
                if w0 != self.width:
                    scale = self.width / float(w0)
                    frame_bgr = cv2.resize(frame_bgr, (self.width, max(1, int(h0 * scale))))
                h, w = frame_bgr.shape[:2]

                rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
                ts_ms = int(now * 1000)
                try:
                    landmarks, world_landmarks = engine.detect(rgb, ts_ms)
                except Exception as e:
                    self._push_status({"type": "error", "message": f"Pose inference failed: {e}"})
                    landmarks, world_landmarks = None, None

                metrics = self.computer.update(landmarks, now)
                phase, report = self.detector.update(now, landmarks, world_landmarks, metrics)
                if report is not None:
                    with self.lock:
                        self.pending_swings.append(report)
                        if self.coach and not self.coach.submit(report):
                            # Still coaching the previous swing. Say so rather than
                            # queueing advice that would arrive too late to act on.
                            self._push_status({"type": "coach_skipped", "swing_id": report.get("id")})

                ok2, buf = cv2.imencode(".jpg", frame_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), self.jpeg_quality])
                jpeg_bytes = buf.tobytes() if ok2 else None
                if jpeg_bytes is not None:
                    with _latest_frame_lock:
                        _latest_frame_jpeg = jpeg_bytes

                if now - last_emit >= min_interval:
                    last_emit = now
                    if len(recent_frame_times) >= 2:
                        span = recent_frame_times[-1] - recent_frame_times[0]
                        actual_fps = (len(recent_frame_times) - 1) / span if span > 1e-6 else 0.0
                    else:
                        actual_fps = 0.0
                    frame_msg = {
                        "type": "frame",
                        "t": round(now, 3),
                        "w": w,
                        "h": h,
                        "fps": round(actual_fps, 2),
                        "jpeg": base64.b64encode(jpeg_bytes).decode("ascii") if jpeg_bytes else None,
                        "landmarks": landmarks,
                        "phase": phase,
                        "metrics": metrics,
                    }
                    with self.lock:
                        self.latest_frame = frame_msg
        finally:
            cap.release()
            engine.close()


@app.websocket("/ws/live")
async def ws_live(
    websocket: WebSocket,
    camera: str = "0",
    source: str | None = None,
    model: str = "lite",
    handedness: str = "auto",
    aspect: str = "4:3",
    coach: int = 1,
    coach_voice: int = 1,
    fps: int = 20,
    jpeg_quality: int = 60,
    width: int = 640,
):
    await websocket.accept()

    if model not in ("lite", "heavy"):
        await websocket.send_text(json.dumps({"type": "error", "message": f"unknown model '{model}'"}))
        await websocket.close()
        return

    session = LiveSession(camera=source or camera, model=model, handedness=handedness, fps=fps, jpeg_quality=jpeg_quality, width=width, aspect=aspect,
                          coach=bool(coach), coach_voice=bool(coach_voice))
    session.start()

    send_interval = 1.0 / max(1, fps)

    async def sender():
        last_sent_t = None
        while True:
            for msg in session.pop_status():
                await websocket.send_text(json.dumps(msg))
            for swing_report in session.pop_swings():
                await websocket.send_text(json.dumps({"type": "swing", "swing": swing_report}))
            frame_msg = session.get_latest_frame()
            if frame_msg is not None and frame_msg.get("t") != last_sent_t:
                last_sent_t = frame_msg.get("t")
                await websocket.send_text(json.dumps(frame_msg))
            await asyncio.sleep(send_interval)

    async def receiver():
        while True:
            msg = await websocket.receive_text()
            try:
                data = json.loads(msg)
            except (json.JSONDecodeError, TypeError):
                continue
            mtype = data.get("type")
            if mtype == "set":
                if "handedness" in data:
                    session.set_handedness(data["handedness"])
            elif mtype == "reset":
                session.reset()

    sender_task = asyncio.create_task(sender())
    receiver_task = asyncio.create_task(receiver())
    try:
        done, pending = await asyncio.wait({sender_task, receiver_task}, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        for task in done:
            exc = task.exception()
            if exc and not isinstance(exc, (WebSocketDisconnect, asyncio.CancelledError)):
                raise exc
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        session.stop()
