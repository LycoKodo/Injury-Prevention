"""Pure-numpy biomechanics computations. No I/O.

Turns a stream of 33-point MediaPipe pose landmarks into the LiveMetrics
dict defined in docs/PROTOCOL.md. Includes light exponential smoothing on
landmark positions and on angular velocities so the UI doesn't jitter.
"""
from __future__ import annotations

import math
from collections import deque
from typing import Optional

import numpy as np

# MediaPipe pose landmark indices we care about.
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_PINKY, R_PINKY = 17, 18
L_INDEX, R_INDEX = 19, 20
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28

HANDEDNESS_WINDOW_S = 2.0
MIN_HANDEDNESS_DATA_S = 1.0  # below this, fall back to default 'right'

MIN_WRIST_VISIBILITY = 0.5  # ignore wrist speed when the wrist is occluded / guessed
LANDMARK_SMOOTHING_ALPHA = 0.55  # higher = less smoothing / more responsive
VELOCITY_SMOOTHING_ALPHA = 0.35


# --------------------------------------------------------------------------
# Pure geometry helpers (all take/return plain floats or np arrays; no state)
# --------------------------------------------------------------------------

def angle_3pt(a, b, c) -> float:
    """Angle in degrees at vertex b, between rays b->a and b->c.

    Uses x,y,z (3D) when provided; points may be [x,y,z] or [x,y,z,vis] or
    plain [x, y]. 180 degrees = a, b, c collinear with b in the middle
    (i.e. a "straight" joint); 0 degrees = a and c coincide direction-wise.
    """
    a = np.asarray(a, dtype=float)[:3] if len(a) >= 3 else _pad3(a)
    b = np.asarray(b, dtype=float)[:3] if len(b) >= 3 else _pad3(b)
    c = np.asarray(c, dtype=float)[:3] if len(c) >= 3 else _pad3(c)
    v1 = a - b
    v2 = c - b
    n1 = np.linalg.norm(v1)
    n2 = np.linalg.norm(v2)
    if n1 < 1e-9 or n2 < 1e-9:
        return 0.0
    cosang = np.dot(v1, v2) / (n1 * n2)
    cosang = float(np.clip(cosang, -1.0, 1.0))
    return math.degrees(math.acos(cosang))


def _pad3(p):
    p = list(p) + [0.0]
    return np.asarray(p[:3], dtype=float)


def line_angle_deg(p_from, p_to) -> float:
    """Angle (degrees, mod 180) of the line p_from->p_to in the image (x,y) plane.

    Mod-180 because a line has no inherent direction; this keeps the angle
    stable regardless of which end is "left" vs "right" for a given frame.
    """
    dx = p_to[0] - p_from[0]
    dy = p_to[1] - p_from[1]
    ang = math.degrees(math.atan2(dy, dx))
    return ang % 180.0


def angle_diff_mod180(a: float, b: float) -> float:
    """Shortest signed difference a-b for mod-180 angles, result in [-90, 90]."""
    d = (a - b + 90.0) % 180.0 - 90.0
    return d


def midpoint(a, b):
    return [(a[i] + b[i]) / 2.0 for i in range(min(len(a), len(b)))]


# --------------------------------------------------------------------------
# Stateful per-stream metrics computer
# --------------------------------------------------------------------------

class LiveMetricsComputer:
    """Consumes (landmarks, t) frames in order, emits LiveMetrics dicts.

    One instance per live stream / analyze job. Not thread-safe; callers
    must serialize update() calls.
    """

    def __init__(self, handedness: str = "auto"):
        self.handedness_mode = handedness
        self._current_handedness = "right"
        self._smoothed: Optional[np.ndarray] = None  # (33,4)
        self._prev_t: Optional[float] = None
        self._prev_positions: dict[str, Optional[list]] = {"left": None, "right": None}
        self._speed_hist: dict[str, deque] = {"left": deque(), "right": deque()}
        self._first_t: Optional[float] = None

        self._smoothed_wrist_speed = 0.0
        self._smoothed_hip_speed = 0.0
        self._smoothed_shoulder_speed = 0.0
        self._prev_hip_angle: Optional[float] = None
        self._prev_shoulder_angle: Optional[float] = None

    def set_handedness(self, mode: str):
        if mode not in ("auto", "left", "right"):
            raise ValueError("handedness must be auto|left|right")
        self.handedness_mode = mode

    def reset(self):
        self.__init__(self.handedness_mode)

    @property
    def handedness(self) -> str:
        return self._current_handedness

    def update(self, landmarks: Optional[list], t: float) -> dict:
        """Advance the state machine by one frame. Returns a LiveMetrics dict.

        `landmarks` is 33x[x,y,z,vis] or None if no pose was detected this
        frame (all metric fields come back None but handedness is preserved).
        """
        if landmarks is None:
            self._prev_t = t
            return self._empty_metrics()

        arr = np.asarray(landmarks, dtype=float)
        if self._smoothed is None or self._smoothed.shape != arr.shape:
            self._smoothed = arr.copy()
        else:
            a = LANDMARK_SMOOTHING_ALPHA
            self._smoothed = a * arr + (1 - a) * self._smoothed
        lm = self._smoothed

        dt = None
        if self._prev_t is not None and t > self._prev_t:
            dt = t - self._prev_t
        if self._first_t is None:
            self._first_t = t

        # --- wrist speeds for both sides (used for handedness + reporting) ---
        wrist_speeds = {}
        for side, idx in (("left", L_WRIST), ("right", R_WRIST)):
            pos = lm[idx][:2]
            speed = 0.0
            visible = arr[idx][3] >= MIN_WRIST_VISIBILITY if arr.shape[1] > 3 else True
            if dt and visible and self._prev_positions[side] is not None:
                d = np.linalg.norm(np.asarray(pos) - np.asarray(self._prev_positions[side]))
                speed = float(d / dt)
            self._prev_positions[side] = pos
            wrist_speeds[side] = speed
            hist = self._speed_hist[side]
            hist.append((t, speed))
            while hist and t - hist[0][0] > HANDEDNESS_WINDOW_S:
                hist.popleft()

        self._update_handedness(t)
        side = self._current_handedness
        other = "left" if side == "right" else "right"

        shoulder_i = R_SHOULDER if side == "right" else L_SHOULDER
        elbow_i = R_ELBOW if side == "right" else L_ELBOW
        wrist_i = R_WRIST if side == "right" else L_WRIST
        hip_i = R_HIP if side == "right" else L_HIP
        index_i = R_INDEX if side == "right" else L_INDEX

        shoulder = lm[shoulder_i]
        elbow = lm[elbow_i]
        wrist = lm[wrist_i]
        hip = lm[hip_i]
        index_pt = lm[index_i]

        elbow_angle = angle_3pt(shoulder, elbow, wrist)
        shoulder_abduction = angle_3pt(elbow, shoulder, hip)
        wrist_extension = 180.0 - angle_3pt(elbow, wrist, index_pt)

        l_hip, r_hip = lm[L_HIP], lm[R_HIP]
        l_sh, r_sh = lm[L_SHOULDER], lm[R_SHOULDER]
        l_knee, r_knee = lm[L_KNEE], lm[R_KNEE]
        l_ankle, r_ankle = lm[L_ANKLE], lm[R_ANKLE]

        hip_angle = line_angle_deg(l_hip, r_hip)
        shoulder_angle = line_angle_deg(l_sh, r_sh)
        hip_shoulder_separation = abs(angle_diff_mod180(shoulder_angle, hip_angle))

        knee_flexion = (
            (180.0 - angle_3pt(l_hip, l_knee, l_ankle))
            + (180.0 - angle_3pt(r_hip, r_knee, r_ankle))
        ) / 2.0

        mid_sh = midpoint(l_sh, r_sh)
        mid_hip = midpoint(l_hip, r_hip)
        vx = mid_sh[0] - mid_hip[0]
        vy = mid_sh[1] - mid_hip[1]
        lean = math.degrees(math.atan2(vx, -vy))  # 0 = perfectly upright
        sign = 1.0 if side == "right" else -1.0
        trunk_lateral_flexion = lean * sign

        wrist_speed_raw = wrist_speeds[side]
        self._smoothed_wrist_speed = _ema(self._smoothed_wrist_speed, wrist_speed_raw, VELOCITY_SMOOTHING_ALPHA)

        hip_rotation_speed_raw = 0.0
        shoulder_rotation_speed_raw = 0.0
        if dt and self._prev_hip_angle is not None:
            hip_rotation_speed_raw = abs(angle_diff_mod180(hip_angle, self._prev_hip_angle)) / dt
        if dt and self._prev_shoulder_angle is not None:
            shoulder_rotation_speed_raw = abs(angle_diff_mod180(shoulder_angle, self._prev_shoulder_angle)) / dt
        self._prev_hip_angle = hip_angle
        self._prev_shoulder_angle = shoulder_angle
        self._smoothed_hip_speed = _ema(self._smoothed_hip_speed, hip_rotation_speed_raw, VELOCITY_SMOOTHING_ALPHA)
        self._smoothed_shoulder_speed = _ema(self._smoothed_shoulder_speed, shoulder_rotation_speed_raw, VELOCITY_SMOOTHING_ALPHA)

        self._prev_t = t

        return {
            "elbow_angle": round(elbow_angle, 2),
            "shoulder_abduction": round(shoulder_abduction, 2),
            "hip_shoulder_separation": round(hip_shoulder_separation, 2),
            "knee_flexion": round(knee_flexion, 2),
            "trunk_lateral_flexion": round(trunk_lateral_flexion, 2),
            "wrist_extension": round(wrist_extension, 2),
            "wrist_speed": round(self._smoothed_wrist_speed, 4),
            "hip_rotation_speed": round(self._smoothed_hip_speed, 2),
            "shoulder_rotation_speed": round(self._smoothed_shoulder_speed, 2),
            "handedness": self._current_handedness,
        }

    def _update_handedness(self, t: float):
        if self.handedness_mode in ("left", "right"):
            self._current_handedness = self.handedness_mode
            return
        span = t - self._first_t if self._first_t is not None else 0.0
        if span < MIN_HANDEDNESS_DATA_S:
            self._current_handedness = "right"
            return
        left_sum = sum(s for _, s in self._speed_hist["left"])
        right_sum = sum(s for _, s in self._speed_hist["right"])
        self._current_handedness = "right" if right_sum >= left_sum else "left"

    def _empty_metrics(self) -> dict:
        return {
            "elbow_angle": None,
            "shoulder_abduction": None,
            "hip_shoulder_separation": None,
            "knee_flexion": None,
            "trunk_lateral_flexion": None,
            "wrist_extension": None,
            "wrist_speed": None,
            "hip_rotation_speed": None,
            "shoulder_rotation_speed": None,
            "handedness": self._current_handedness,
        }


def _ema(prev: float, new: float, alpha: float) -> float:
    return alpha * new + (1 - alpha) * prev
