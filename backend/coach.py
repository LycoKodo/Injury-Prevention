"""Talking coach: turns a SwingReport into one or two spoken "problem / fix" cues.

Design goals, in priority order:
  1. Real time. Coaching a swing that happened 20 seconds ago is useless, so the
     worker keeps at most one job and DROPS anything that arrives while it is busy.
  2. Short. The player is on a court, not reading a report. Hard word budget, and
     playback is killed if it somehow runs past MAX_SPEECH_SECONDS.
  3. Always works. Cerebras and ElevenLabs are best-effort; if either is
     unreachable, out of quota or unauthorized, we fall back to locally generated
     text and the macOS system voice rather than going silent.
"""
from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Callable, Optional

_HERE = Path(__file__).resolve().parent

# --- budgets -------------------------------------------------------------
MAX_SPEECH_SECONDS = 30.0     # hard ceiling required by the product spec
WORDS_PER_SECOND = 2.7        # conversational TTS pace
MAX_WORDS = int(MAX_SPEECH_SECONDS * WORDS_PER_SECOND * 0.7)  # ~56, leaves headroom
MAX_ITEMS = 2

CEREBRAS_URL = "https://api.cerebras.ai/v1/chat/completions"
ELEVEN_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice}"

DEFAULT_MODEL = "gpt-oss-120b"
DEFAULT_VOICE = "21m00Tcm4TlvDq8ikWAM"   # Rachel, a stock ElevenLabs voice
DEFAULT_TTS_MODEL = "eleven_flash_v2_5"  # lowest-latency ElevenLabs model


# --- environment ---------------------------------------------------------
def load_env(path: Path = _HERE / ".env") -> None:
    """Minimal .env loader so secrets stay out of the source tree."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


_ca_cache: Optional[str] = None


def ca_bundle() -> Optional[str]:
    """Path to a CA bundle that includes the macOS keychain roots.

    Networks that intercept TLS present a locally-trusted root that Python's
    bundled certifi store knows nothing about, so every HTTPS call fails with
    CERTIFICATE_VERIFY_FAILED even though the browser works fine. Exporting the
    system roots once fixes that without disabling verification.
    """
    global _ca_cache
    if _ca_cache is not None:
        return _ca_cache or None
    if sys.platform != "darwin":
        _ca_cache = ""
        return None
    out = _HERE / ".cache" / "macos-roots.pem"
    try:
        if not out.exists() or out.stat().st_size < 1000:
            out.parent.mkdir(parents=True, exist_ok=True)
            chunks = []
            for kc in ("/System/Library/Keychains/SystemRootCertificates.keychain",
                       "/Library/Keychains/System.keychain"):
                r = subprocess.run(["security", "find-certificate", "-a", "-p", kc],
                                   capture_output=True, text=True, timeout=30)
                if r.returncode == 0:
                    chunks.append(r.stdout)
            if not chunks:
                _ca_cache = ""
                return None
            out.write_text("\n".join(chunks))
        _ca_cache = str(out)
    except Exception:
        _ca_cache = ""
    return _ca_cache or None


# --- text helpers --------------------------------------------------------
def _clean(s: str) -> str:
    s = re.sub(r"\s+", " ", str(s or "")).strip()
    s = s.replace("--", ",").replace("—", ",")
    # Spoken-form fixes: a TTS voice reads "deg" as "deg".
    s = re.sub(r"\bdeg\b\.?", "degrees", s)
    s = re.sub(r"(\d)\s*°", r"\1 degrees", s)
    s = re.sub(r"\s+([,.;:])", r"\1", s)
    return s.strip(" ,;:")


def trim_to_words(text: str, limit: int = MAX_WORDS) -> str:
    words = text.split()
    if len(words) <= limit:
        return text
    return " ".join(words[:limit]).rstrip(",.;:") + "."


def items_to_speech(items: list[dict]) -> str:
    parts = []
    for it in items[:MAX_ITEMS]:
        problem = _clean(it.get("problem"))
        fix = _clean(it.get("fix"))
        if not problem and not fix:
            continue
        parts.append(f"{problem.rstrip('.')}. {fix.rstrip('.')}.")
    return trim_to_words(" ".join(parts))


# --- local (no-network) generation ---------------------------------------
_FIXES = {
    "elbow": "Drive through the ball with a firmer, straighter arm.",
    "shoulder": "Keep your hitting elbow below shoulder height.",
    "wrist": "Flatten the wrist and lock it through contact.",
    "lower_back": "Rotate your body instead of leaning sideways.",
    "knee": "Bend into the shot and push up through the legs.",
    "chain": "Start the swing from your legs and hips, not your arm.",
}


def local_items(report: dict) -> list[dict]:
    """Derive cues from the scoring output. Deterministic and instant."""
    feedback = [f for f in (report.get("feedback") or []) if f.get("severity") in ("danger", "warn")]
    rank = {"danger": 0, "warn": 1}
    feedback.sort(key=lambda f: rank.get(f.get("severity"), 9))

    items = []
    for f in feedback[:MAX_ITEMS]:
        joint = f.get("joint", "chain")
        detail = _clean(f.get("detail"))
        problem = detail.split(",")[0] if detail else _clean(f.get("title"))
        items.append({"problem": trim_to_words(problem, 22),
                      "fix": _FIXES.get(joint, "Smooth the swing out and stay relaxed."),
                      "joint": joint})

    if not items:
        eff = report.get("efficiency_score")
        items.append({"problem": f"Clean swing, efficiency {eff}." if eff is not None else "Clean swing.",
                      "fix": "Keep that shape and add a little more hip turn.",
                      "joint": "chain"})
    return items


# --- Cerebras ------------------------------------------------------------
SYSTEM_PROMPT = (
    "You are a tennis coach speaking OUT LOUD to a player who just hit a forehand. "
    "You get biomechanics measured from video. Pick only the ONE or TWO highest-priority "
    "things to fix, preferring whatever carries real injury risk. "
    "For each, give a 'problem' (what went wrong, plain language, no jargon, no numbers "
    "unless one number makes it click) and a 'fix' (one concrete physical cue). "
    "Speak in second person, warm and direct, like a coach on court. "
    f"Your ENTIRE reply must be under {MAX_WORDS} spoken words. "
    'Reply with JSON only: {"items":[{"problem":"...","fix":"..."}]}'
)


def _swing_facts(report: dict) -> str:
    m = report.get("metrics_at_contact") or {}
    kc = report.get("kinetic_chain") or {}
    def g(d, k):
        v = d.get(k)
        return "n/a" if v is None else (f"{v:.0f}" if isinstance(v, (int, float)) else str(v))
    return (
        f"efficiency={report.get('efficiency_score')}/100 injury_risk={report.get('injury_risk_score')}/100\n"
        f"risk_by_joint={json.dumps(report.get('risk_by_joint') or {})}\n"
        f"force_share_pct={json.dumps(report.get('force_distribution') or {})}\n"
        f"at_contact: elbow={g(m,'elbow_angle')}deg shoulder_abduction={g(m,'shoulder_abduction')}deg "
        f"wrist_extension={g(m,'wrist_extension')}deg trunk_lean={g(m,'trunk_lateral_flexion')}deg "
        f"knee_flexion={g(m,'knee_flexion')}deg hip_shoulder_separation={g(m,'hip_shoulder_separation')}deg\n"
        f"kinetic_chain_in_order={kc.get('sequencing_ok')} "
        f"hip_to_shoulder_lag_ms={kc.get('lag_hip_to_shoulder_ms')} "
        f"shoulder_to_arm_lag_ms={kc.get('lag_shoulder_to_arm_ms')}"
    )


def cerebras_items(report: dict, timeout: float = 6.0) -> Optional[list[dict]]:
    key = os.environ.get("CEREBRAS_API_KEY")
    if not key:
        return None
    try:
        import requests
    except Exception:
        return None
    body = {
        "model": os.environ.get("CEREBRAS_MODEL", DEFAULT_MODEL),
        "temperature": 0.3,
        "max_completion_tokens": 300,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _swing_facts(report)},
        ],
    }
    try:
        r = requests.post(CEREBRAS_URL, json=body, timeout=timeout,
                          headers={"Authorization": f"Bearer {key}"}, verify=ca_bundle() or True)
        if r.status_code != 200:
            return None
        content = r.json()["choices"][0]["message"]["content"]
        data = json.loads(content)
        items = data.get("items") or []
        out = []
        for it in items[:MAX_ITEMS]:
            if it.get("problem") or it.get("fix"):
                out.append({"problem": _clean(it.get("problem")), "fix": _clean(it.get("fix"))})
        return out or None
    except Exception:
        return None


# --- ElevenLabs ----------------------------------------------------------
def elevenlabs_mp3(text: str, timeout: float = 8.0) -> Optional[bytes]:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        return None
    try:
        import requests
    except Exception:
        return None
    voice = os.environ.get("ELEVENLABS_VOICE_ID", DEFAULT_VOICE)
    try:
        r = requests.post(
            ELEVEN_URL.format(voice=voice),
            params={"output_format": "mp3_22050_32"},
            json={"text": text, "model_id": os.environ.get("ELEVENLABS_MODEL", DEFAULT_TTS_MODEL)},
            headers={"xi-api-key": key, "Content-Type": "application/json"},
            timeout=timeout, verify=ca_bundle() or True,
        )
        if r.status_code != 200 or not r.content or r.content[:1] == b"{":
            return None
        return r.content
    except Exception:
        return None


class Speaker:
    """Plays coach audio, never letting one clip outlive MAX_SPEECH_SECONDS."""

    def __init__(self):
        self._proc: Optional[subprocess.Popen] = None
        self._lock = threading.Lock()

    def stop(self):
        with self._lock:
            p, self._proc = self._proc, None
        if p and p.poll() is None:
            try:
                p.kill()
            except Exception:
                pass

    def _run(self, cmd: list[str]) -> None:
        self.stop()
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            return
        with self._lock:
            self._proc = p
        try:
            p.wait(timeout=MAX_SPEECH_SECONDS)
        except subprocess.TimeoutExpired:
            self.stop()

    def speak(self, text: str) -> str:
        """Returns which voice actually spoke: 'elevenlabs', 'system' or 'none'."""
        mp3 = elevenlabs_mp3(text)
        if mp3:
            try:
                with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as fh:
                    fh.write(mp3)
                    path = fh.name
                self._run(["afplay", path])
                try:
                    os.unlink(path)
                except Exception:
                    pass
                return "elevenlabs"
            except Exception:
                pass
        if sys.platform == "darwin":
            # Render first, then play. Calling `say` so it drives the audio device
            # directly blocks indefinitely when the backend runs without an audio
            # session, whereas rendering to a file and using afplay always works.
            path = None
            try:
                with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as fh:
                    path = fh.name
                # -r is words per minute; keeps a full-budget line inside the cap.
                r = subprocess.run(["say", "-r", "185", "-o", path, text],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=MAX_SPEECH_SECONDS)
                if r.returncode == 0 and os.path.getsize(path) > 0:
                    self._run(["afplay", path])
                    return "system"
            except Exception:
                pass
            finally:
                if path:
                    try:
                        os.unlink(path)
                    except Exception:
                        pass
        return "none"


# --- worker --------------------------------------------------------------
class Coach:
    """Single-slot background coach. Drops swings that arrive while busy."""

    def __init__(self, on_result: Callable[[dict], None], speak: bool = True):
        self.on_result = on_result
        self.speak_enabled = speak
        self._q: queue.Queue = queue.Queue(maxsize=1)
        self._stop = threading.Event()
        self._speaker = Speaker()
        self._busy = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def submit(self, report: dict) -> bool:
        """Returns False if the swing was dropped to stay real time."""
        if self._busy.is_set():
            return False
        try:
            self._q.put_nowait(report)
            return True
        except queue.Full:
            return False

    def stop(self):
        self._stop.set()
        self._speaker.stop()

    def _loop(self):
        while not self._stop.is_set():
            try:
                report = self._q.get(timeout=0.25)
            except queue.Empty:
                continue
            self._busy.set()
            try:
                self._handle(report)
            except Exception:
                pass
            finally:
                self._busy.clear()

    def _handle(self, report: dict):
        t0 = time.monotonic()
        items = cerebras_items(report)
        source = "cerebras" if items else "local"
        if not items:
            items = local_items(report)
        text = items_to_speech(items)
        gen_ms = int((time.monotonic() - t0) * 1000)

        self.on_result({
            "type": "coach", "swing_id": report.get("id"), "items": items[:MAX_ITEMS],
            "text": text, "source": source, "voice": "pending" if self.speak_enabled else "off",
            "generate_ms": gen_ms,
        })

        voice = "off"
        if self.speak_enabled and text:
            voice = self._speaker.speak(text)
        self.on_result({
            "type": "coach_spoken", "swing_id": report.get("id"), "voice": voice,
            "total_ms": int((time.monotonic() - t0) * 1000),
        })
