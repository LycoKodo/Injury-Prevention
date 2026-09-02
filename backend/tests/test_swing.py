import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import biomechanics as bio
from swing_detector import SwingDetector


def _base_landmarks():
    lm = [[0.5, 0.5, 0.0, 1.0] for _ in range(33)]
    lm[bio.L_ANKLE] = [0.42, 0.95, 0.0, 1.0]
    lm[bio.R_ANKLE] = [0.58, 0.95, 0.0, 1.0]
    return lm


def _rotate(center, half_width, angle_deg):
    """Return (left_pt, right_pt) for a line of given half-width rotated
    by angle_deg (degrees) around center, in the image x,y plane."""
    a = math.radians(angle_deg)
    dx, dy = half_width * math.cos(a), half_width * math.sin(a)
    left = [center[0] - dx, center[1] - dy]
    right = [center[0] + dx, center[1] + dy]
    return left, right


def _smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def _bell(t, t_peak, sigma):
    return math.exp(-((t - t_peak) ** 2) / (2 * sigma ** 2))


def generate_swing_frames(
    n_frames=90,
    fps=45.0,
    hip_amplitude=25.0,
    separation_amplitude=34.0,
    hip_delay=0.0,
    hip_duration=0.45,
    separation_delay=0.05,
    separation_duration=0.35,
    knee_amplitude=35.0,
    elbow_target_deg=155.0,
    wrist_peak_speed=3.0,
    t_peak=0.50,
    sigma=0.08,
):
    """Builds a synthetic forehand: the hip line rotates first (if
    hip_amplitude>0), hip-shoulder separation grows monotonically on top of
    that (so the shoulder line rotates further and a bit later), while the
    hitting (right) wrist sweeps from behind the body to in front with a
    bell-shaped speed profile, and knees bend during preparation.
    """
    dt = 1.0 / fps
    hip_center = [0.5, 0.55]
    shoulder_center = [0.5, 0.30]
    hip_half_width = 0.09
    shoulder_half_width = 0.10

    wrist_start = [0.80, 0.55]
    wrist_end = [0.20, 0.42]
    direction = [wrist_end[0] - wrist_start[0], wrist_end[1] - wrist_start[1]]
    dlen = math.hypot(*direction)
    unit = [direction[0] / dlen, direction[1] / dlen]

    frames = []
    wrist_pos = list(wrist_start)
    for i in range(n_frames):
        t = i * dt

        hip_prog = _smoothstep((t - hip_delay) / hip_duration) if hip_amplitude else 0.0
        hip_angle = hip_amplitude * hip_prog
        sep_prog = _smoothstep((t - separation_delay) / separation_duration)
        separation = separation_amplitude * sep_prog
        shoulder_angle = hip_angle + separation

        knee_prog = _bell(t, 0.45, 0.35)
        knee_bend = knee_amplitude * knee_prog  # degrees of knee flexion (approx)

        speed = wrist_peak_speed * _bell(t, t_peak, sigma)
        if i > 0:
            wrist_pos = [wrist_pos[0] + unit[0] * speed * dt, wrist_pos[1] + unit[1] * speed * dt]

        lm = _base_landmarks()
        l_sh, r_sh = _rotate(shoulder_center, shoulder_half_width, shoulder_angle)
        l_hip, r_hip = _rotate(hip_center, hip_half_width, hip_angle)
        lm[bio.L_SHOULDER] = l_sh + [0.0, 1.0]
        lm[bio.R_SHOULDER] = r_sh + [0.0, 1.0]
        lm[bio.L_HIP] = l_hip + [0.0, 1.0]
        lm[bio.R_HIP] = r_hip + [0.0, 1.0]

        # knee: bend forward in x proportional to knee_bend (rough proxy)
        knee_x_shift = 0.10 * (knee_bend / 45.0)
        lm[bio.L_KNEE] = [0.42 + knee_x_shift, 0.75, 0.0, 1.0]
        lm[bio.R_KNEE] = [0.58 - knee_x_shift, 0.75, 0.0, 1.0]

        # left (non-hitting) arm stays relaxed at side
        lm[bio.L_ELBOW] = [l_sh[0] - 0.02, l_sh[1] + 0.15, 0.0, 1.0]
        lm[bio.L_WRIST] = [l_sh[0] - 0.03, l_sh[1] + 0.30, 0.0, 1.0]
        lm[bio.L_INDEX] = [l_sh[0] - 0.03, l_sh[1] + 0.33, 0.0, 1.0]

        # hitting (right) arm: wrist follows the swing path; elbow placed to
        # hit roughly elbow_target_deg using a perpendicular offset.
        r_shoulder_pt = r_sh
        seg = [wrist_pos[0] - r_shoulder_pt[0], wrist_pos[1] - r_shoulder_pt[1]]
        seg_len = math.hypot(*seg) or 1e-6
        seg_u = [seg[0] / seg_len, seg[1] / seg_len]
        perp = [-seg_u[1], seg_u[0]]
        # bend factor: 0 -> elbow on the straight line (180deg), larger -> more bend
        bend_rad = math.radians(180.0 - elbow_target_deg)
        offset_mag = seg_len * 0.5 * math.sin(bend_rad / 2.0) * 2.2
        elbow_pt = [
            r_shoulder_pt[0] + seg_u[0] * seg_len * 0.5 + perp[0] * offset_mag,
            r_shoulder_pt[1] + seg_u[1] * seg_len * 0.5 + perp[1] * offset_mag,
        ]
        lm[bio.R_ELBOW] = elbow_pt + [0.0, 1.0]
        lm[bio.R_WRIST] = list(wrist_pos) + [0.0, 1.0]
        # index continues past the wrist along the forearm->hand direction (straight wrist)
        hand_dir = [wrist_pos[0] - elbow_pt[0], wrist_pos[1] - elbow_pt[1]]
        hlen = math.hypot(*hand_dir) or 1e-6
        hand_u = [hand_dir[0] / hlen, hand_dir[1] / hlen]
        lm[bio.R_INDEX] = [wrist_pos[0] + hand_u[0] * 0.03, wrist_pos[1] + hand_u[1] * 0.03, 0.0, 1.0]

        frames.append((t, lm))

    return frames


def _run_pipeline(frames, handedness="right"):
    computer = bio.LiveMetricsComputer(handedness=handedness)
    detector = SwingDetector()
    reports = []
    phases = []
    for t, lm in frames:
        metrics = computer.update(lm, t)
        phase, report = detector.update(t, lm, None, metrics)
        phases.append(phase)
        if report is not None:
            reports.append(report)
    return reports, phases


def test_normal_swing_detected_and_scored_well():
    frames = generate_swing_frames()
    reports, phases = _run_pipeline(frames)

    assert len(reports) >= 1, f"expected a swing to be detected; phases seen: {sorted(set(phases))}"
    report = reports[0]

    assert report["kinetic_chain"]["sequencing_ok"] is True
    total = sum(report["force_distribution"].values())
    assert total == 100
    assert 40 <= report["efficiency_score"] <= 100
    assert report["injury_risk_score"] < 50


def test_arm_only_swing_riskier_and_mentions_elbow():
    frames = generate_swing_frames(
        hip_amplitude=0.0,
        separation_amplitude=55.0,
        knee_amplitude=0.0,
        elbow_target_deg=90.0,
    )
    reports, phases = _run_pipeline(frames)
    assert len(reports) >= 1, f"expected a swing to be detected; phases seen: {sorted(set(phases))}"
    arm_report = reports[0]

    normal_frames = generate_swing_frames()
    normal_reports, _ = _run_pipeline(normal_frames)
    assert len(normal_reports) >= 1
    normal_report = normal_reports[0]

    assert arm_report["injury_risk_score"] > normal_report["injury_risk_score"]
    joints_mentioned = {item["joint"] for item in arm_report["feedback"]}
    assert "elbow" in joints_mentioned
