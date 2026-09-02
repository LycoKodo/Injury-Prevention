"""Thin wrapper around MediaPipe Tasks PoseLandmarker.

Runs fully on-device. Handles the lite/heavy model choice and VIDEO running
mode, which requires monotonically increasing timestamps (in ms) per
landmarker instance.
"""
from __future__ import annotations

import os
import threading
from typing import Optional

import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision

_MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
_MODEL_PATHS = {
    "lite": os.path.join(_MODEL_DIR, "pose_landmarker_lite.task"),
    "heavy": os.path.join(_MODEL_DIR, "pose_landmarker_heavy.task"),
}


def landmarks_to_list(landmark_list) -> list[list[float]]:
    """Convert a mediapipe landmark list into [[x,y,z,vis], ...]."""
    return [[lm.x, lm.y, lm.z, lm.visibility] for lm in landmark_list]


class PoseEngine:
    """Wraps a PoseLandmarker in VIDEO mode with a strictly increasing clock.

    Not thread-safe for concurrent detect() calls on the same instance;
    callers (server.py) must serialize access per engine (one engine per
    live stream / analyze job).
    """

    def __init__(self, model: str = "lite"):
        if model not in _MODEL_PATHS:
            raise ValueError(f"unknown model '{model}', expected 'lite' or 'heavy'")
        self.model = model
        self._path = _MODEL_PATHS[model]
        if not os.path.exists(self._path):
            raise FileNotFoundError(f"pose model file missing: {self._path}")
        opts = vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=self._path),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=1,
        )
        self._landmarker = vision.PoseLandmarker.create_from_options(opts)
        self._last_ts_ms = -1
        self._lock = threading.Lock()

    def detect(self, rgb_frame, timestamp_ms: int):
        """Run pose detection on an RGB ndarray (H,W,3, uint8).

        timestamp_ms must be monotonically increasing (>= previous + 1);
        the engine will bump it forward automatically if a caller ever
        supplies a non-increasing value (e.g. duplicate frame timestamps).

        Returns (landmarks, world_landmarks): each is a list of [x,y,z,vis]
        (world has no visibility so vis=0.0) or None if no pose detected.
        """
        with self._lock:
            if timestamp_ms <= self._last_ts_ms:
                timestamp_ms = self._last_ts_ms + 1
            self._last_ts_ms = timestamp_ms
            img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            result = self._landmarker.detect_for_video(img, timestamp_ms)

        if not result.pose_landmarks:
            return None, None

        landmarks = landmarks_to_list(result.pose_landmarks[0])
        world_landmarks: Optional[list[list[float]]] = None
        if result.pose_world_landmarks:
            world_landmarks = [
                [lm.x, lm.y, lm.z, 0.0] for lm in result.pose_world_landmarks[0]
            ]
        return landmarks, world_landmarks

    def close(self):
        try:
            self._landmarker.close()
        except Exception:
            pass
