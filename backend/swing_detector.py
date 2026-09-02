"""State machine that turns a per-frame LiveMetrics stream into SwingReports.

idle -> preparation -> forward_swing -> contact -> follow_through -> idle

Keeps a rolling buffer (~a few seconds) of per-frame data (landmarks, world
landmarks, metrics, timestamp) so that once a swing completes we can hand
the whole trajectory to scoring.py.
"""
from __future__ import annotations

from collections import deque
from typing import Optional

import scoring

# --- Tunable thresholds (normalized-units/s for wrist speed, deg for angles) ---
PREP_SEPARATION_MIN = 12.0     # hip-shoulder separation (deg) to consider "loading"
PREP_MAX_SPEED = 0.6           # wrist must be relatively slow while preparing
FORWARD_SPEED_THRESHOLD = 0.9  # wrist speed (units/s) that marks forward swing onset
CONTACT_DECAY_RATIO = 0.75     # fraction of peak speed that marks "past contact"
FOLLOW_END_SPEED = 0.35        # wrist speed below which follow-through is "done"
FOLLOW_MAX_S = 0.9             # hard cap on follow-through duration
PREP_TIMEOUT_S = 2.5           # abandon preparation if forward swing never starts
MIN_SWING_DURATION = 0.25      # discard swings shorter than this (noise)
MIN_PEAK_SPEED = 1.0           # discard swings whose peak wrist speed is too low
REFRACTORY_S = 0.5             # cooldown after a swing before a new one can start
BUFFER_SECONDS = 4.0           # rolling history retained for scoring


class SwingDetector:
    def __init__(self):
        self.phase = "idle"
        self.buffer: deque = deque()
        self.prep_start_t: Optional[float] = None
        self.forward_start_t: Optional[float] = None
        self.follow_start_t: Optional[float] = None
        self.peak_speed = 0.0
        self.peak_t: Optional[float] = None
        self.contact_t: Optional[float] = None
        self.last_swing_end_t = -1e9
        self._swing_id = 0

    def reset(self):
        self.__init__()

    def update(self, t: float, landmarks, world_landmarks, metrics: dict):
        """Feed one frame. Returns (phase, swing_report_or_None)."""
        self.buffer.append(
            {"t": t, "landmarks": landmarks, "world_landmarks": world_landmarks, "metrics": metrics}
        )
        while self.buffer and t - self.buffer[0]["t"] > BUFFER_SECONDS:
            self.buffer.popleft()

        if landmarks is None or metrics.get("wrist_speed") is None:
            return self.phase, None

        wrist_speed = metrics["wrist_speed"]
        separation = metrics.get("hip_shoulder_separation") or 0.0

        report = None

        if self.phase == "idle":
            if t - self.last_swing_end_t >= REFRACTORY_S and (
                separation >= PREP_SEPARATION_MIN and wrist_speed <= PREP_MAX_SPEED
            ):
                self.phase = "preparation"
                self.prep_start_t = t

        elif self.phase == "preparation":
            if wrist_speed >= FORWARD_SPEED_THRESHOLD:
                self.phase = "forward_swing"
                self.forward_start_t = t
                self.peak_speed = wrist_speed
                self.peak_t = t
            elif t - self.prep_start_t > PREP_TIMEOUT_S:
                self.phase = "idle"

        elif self.phase == "forward_swing":
            if wrist_speed > self.peak_speed:
                self.peak_speed = wrist_speed
                self.peak_t = t
            elif wrist_speed < self.peak_speed * CONTACT_DECAY_RATIO:
                self.phase = "contact"
                self.contact_t = self.peak_t

        elif self.phase == "contact":
            self.phase = "follow_through"
            self.follow_start_t = t

        elif self.phase == "follow_through":
            if wrist_speed < FOLLOW_END_SPEED or (t - self.follow_start_t) > FOLLOW_MAX_S:
                report = self._finalize(t)
                self.phase = "idle"
                self.last_swing_end_t = t

        return self.phase, report

    def _finalize(self, t_end: float):
        t_start = self.prep_start_t
        if t_start is None:
            return None
        duration = t_end - t_start
        if duration < MIN_SWING_DURATION or self.peak_speed < MIN_PEAK_SPEED:
            return None
        frames = [f for f in self.buffer if t_start <= f["t"] <= t_end]
        if len(frames) < 3:
            return None
        swing_id = self._swing_id + 1
        report = scoring.build_swing_report(
            swing_id=swing_id,
            frames=frames,
            t_start=t_start,
            t_contact=self.contact_t if self.contact_t is not None else t_end,
            t_end=t_end,
        )
        if report is not None:
            self._swing_id = swing_id
        return report
