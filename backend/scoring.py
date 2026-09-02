"""Turns a buffered swing (list of per-frame {t, landmarks, world_landmarks,
metrics}) into a SwingReport dict matching docs/PROTOCOL.md.

All thresholds/weights live in CONFIG so they can be tuned in one place.
"""
from __future__ import annotations

from typing import Optional

# ---------------------------------------------------------------------------
CONFIG = {
    "ideal_distribution": {"legs": 20, "hips": 25, "trunk": 20, "shoulder": 20, "arm": 15},

    # force_distribution: raw-signal weights (proxies from peak angular speeds)
    "force_weights": {
        "legs": 1.0,        # * peak knee-extension speed (deg/s)
        "hips": 1.0,        # * peak hip_rotation_speed (deg/s)
        "trunk": 1.0,       # * peak (shoulder_rotation_speed - hip_rotation_speed)
        "shoulder": 1.0,    # * peak upper-arm (shoulder_abduction) angular speed (deg/s)
        "arm_elbow": 1.0,   # * peak elbow-extension speed (deg/s)
        "arm_wrist_scale": 90.0,  # wrist_speed (units/s) -> comparable deg/s magnitude
    },

    # efficiency sub-score weights (sum to 1.0)
    "efficiency_weights": {
        "sequencing": 0.35,
        "separation": 0.20,
        "knee": 0.15,
        "contact_extension": 0.15,
        "follow_through": 0.15,
    },
    "separation_target": (30.0, 45.0),
    "knee_flexion_target": (30.0, 50.0),
    "contact_elbow_target": (140.0, 170.0),
    "follow_through_target_travel": 0.35,  # normalized-unit wrist travel considered "full"
    "sequencing_max_lag_ms": 300.0,

    # injury risk thresholds
    "elbow_angle_range": (100.0, 175.0),
    "shoulder_abduction_max": 90.0,
    "wrist_extension_max": 30.0,
    "trunk_lateral_flexion_max": 20.0,
    "knee_flexion_range": (10.0, 70.0),
    "arm_dominant_share": 30.0,

    "risk_scale": {"elbow": 40.0, "shoulder": 45.0, "wrist": 30.0, "lower_back": 20.0, "knee": 30.0},
    "risk_weights": {"elbow": 0.25, "shoulder": 0.20, "wrist": 0.15, "lower_back": 0.20, "knee": 0.20},

    "severity_danger": 60.0,
    "severity_warn": 30.0,

    "trajectory_samples": 30,
}


def _clip01(x: float) -> float:
    return max(0.0, min(1.0, x))


def _clip100(x: float) -> float:
    return max(0.0, min(100.0, x))


def _nearest_frame(frames: list[dict], t: float) -> dict:
    return min(frames, key=lambda f: abs(f["t"] - t))


def _series(frames: list[dict], key: str) -> list[tuple[float, float]]:
    out = []
    for f in frames:
        v = f["metrics"].get(key)
        if v is not None:
            out.append((f["t"], v))
    return out


def _peak(series: list[tuple[float, float]]) -> tuple[Optional[float], float]:
    """Returns (t_of_peak, peak_value); (None, 0.0) if empty."""
    if not series:
        return None, 0.0
    t_peak, v_peak = max(series, key=lambda p: p[1])
    return t_peak, v_peak


def _derivative_peak_abs(frames: list[dict], key: str, sign: int = 0) -> float:
    """Peak |d(metric)/dt| across consecutive frames. sign=+1 only counts
    increasing changes, -1 only decreasing, 0 counts both directions."""
    vals = [(f["t"], f["metrics"].get(key)) for f in frames if f["metrics"].get(key) is not None]
    peak = 0.0
    for (t0, v0), (t1, v1) in zip(vals, vals[1:]):
        dt = t1 - t0
        if dt <= 1e-6:
            continue
        d = (v1 - v0) / dt
        if sign > 0 and d < 0:
            continue
        if sign < 0 and d > 0:
            continue
        peak = max(peak, abs(d))
    return peak


def _triangular_score(value: Optional[float], lo: float, hi: float, slack: float) -> float:
    """1.0 inside [lo,hi], falling off linearly to 0 over `slack` outside it."""
    if value is None:
        return 0.5
    if lo <= value <= hi:
        return 1.0
    dist = lo - value if value < lo else value - hi
    return _clip01(1.0 - dist / slack)


def _round_shares(raw: dict[str, float]) -> dict[str, int]:
    total = sum(raw.values())
    if total <= 1e-9:
        n = len(raw)
        even = 100 // n
        out = {k: even for k in raw}
        # dump remainder into first key
        first = next(iter(raw))
        out[first] += 100 - even * n
        return out
    shares = {k: (v / total) * 100.0 for k, v in raw.items()}
    rounded = {k: int(round(v)) for k, v in shares.items()}
    diff = 100 - sum(rounded.values())
    if diff != 0:
        # apply remainder to the largest share for minimal distortion
        biggest = max(rounded, key=lambda k: shares[k])
        rounded[biggest] += diff
    return rounded


def _downsample(frames: list[dict], n: int) -> list[dict]:
    if len(frames) <= n:
        return frames
    step = len(frames) / n
    idxs = sorted({int(i * step) for i in range(n)})
    return [frames[i] for i in idxs]


def build_swing_report(swing_id: int, frames: list[dict], t_start: float, t_contact: float, t_end: float) -> Optional[dict]:
    if not frames:
        return None

    contact_frame = _nearest_frame(frames, t_contact)
    metrics_at_contact = contact_frame["metrics"]

    pre_contact_frames = [f for f in frames if f["t"] <= t_contact] or frames
    post_contact_frames = [f for f in frames if f["t"] >= t_contact] or [contact_frame]

    # ---- kinetic chain sequencing ----
    hip_t, _ = _peak(_series(frames, "hip_rotation_speed"))
    shoulder_t, _ = _peak(_series(frames, "shoulder_rotation_speed"))
    arm_t, _ = _peak(_series(frames, "wrist_speed"))

    lag_hip_to_shoulder_ms = None
    lag_shoulder_to_arm_ms = None
    sequencing_ok = False
    if hip_t is not None and shoulder_t is not None and arm_t is not None:
        lag_hip_to_shoulder_ms = (shoulder_t - hip_t) * 1000.0
        lag_shoulder_to_arm_ms = (arm_t - shoulder_t) * 1000.0
        max_lag = CONFIG["sequencing_max_lag_ms"]
        sequencing_ok = (
            0.0 <= lag_hip_to_shoulder_ms <= max_lag and 0.0 <= lag_shoulder_to_arm_ms <= max_lag
        )

    kinetic_chain = {
        "hip_peak_t": hip_t,
        "shoulder_peak_t": shoulder_t,
        "arm_peak_t": arm_t,
        "sequencing_ok": bool(sequencing_ok),
        "lag_hip_to_shoulder_ms": round(lag_hip_to_shoulder_ms, 1) if lag_hip_to_shoulder_ms is not None else None,
        "lag_shoulder_to_arm_ms": round(lag_shoulder_to_arm_ms, 1) if lag_shoulder_to_arm_ms is not None else None,
    }

    # ---- force distribution (proxies from peak angular speeds) ----
    fw = CONFIG["force_weights"]
    legs_raw = _derivative_peak_abs(frames, "knee_flexion", sign=-1) * fw["legs"]
    _, hip_speed_peak = _peak(_series(frames, "hip_rotation_speed"))
    _, shoulder_speed_peak = _peak(_series(frames, "shoulder_rotation_speed"))
    hips_raw = hip_speed_peak * fw["hips"]
    trunk_raw = max(0.0, shoulder_speed_peak - hip_speed_peak) * fw["trunk"]
    shoulder_raw = _derivative_peak_abs(frames, "shoulder_abduction") * fw["shoulder"]
    elbow_ext_peak = _derivative_peak_abs(frames, "elbow_angle")
    _, wrist_speed_peak = _peak(_series(frames, "wrist_speed"))
    arm_raw = elbow_ext_peak * fw["arm_elbow"] + wrist_speed_peak * fw["arm_wrist_scale"]

    force_distribution = _round_shares(
        {"legs": legs_raw, "hips": hips_raw, "trunk": trunk_raw, "shoulder": shoulder_raw, "arm": arm_raw}
    )

    # ---- efficiency score ----
    ew = CONFIG["efficiency_weights"]
    sep_lo, sep_hi = CONFIG["separation_target"]
    knee_lo, knee_hi = CONFIG["knee_flexion_target"]
    ce_lo, ce_hi = CONFIG["contact_elbow_target"]

    max_separation = max((f["metrics"].get("hip_shoulder_separation") or 0.0) for f in pre_contact_frames)
    max_knee_flexion = max((f["metrics"].get("knee_flexion") or 0.0) for f in pre_contact_frames)

    seq_score = 1.0 if sequencing_ok else 0.4
    sep_score = _triangular_score(max_separation, sep_lo, sep_hi, slack=25.0)
    knee_score = _triangular_score(max_knee_flexion, knee_lo, knee_hi, slack=25.0)
    contact_score = _triangular_score(metrics_at_contact.get("elbow_angle"), ce_lo, ce_hi, slack=35.0)

    ft_positions = [f["landmarks"] for f in post_contact_frames if f["landmarks"] is not None]
    follow_travel = 0.0
    if len(ft_positions) >= 2:
        import math
        side = metrics_at_contact.get("handedness", "right")
        wrist_idx = 16 if side == "right" else 15
        for a, b in zip(ft_positions, ft_positions[1:]):
            follow_travel += math.hypot(b[wrist_idx][0] - a[wrist_idx][0], b[wrist_idx][1] - a[wrist_idx][1])
    follow_score = _clip01(follow_travel / CONFIG["follow_through_target_travel"])

    efficiency_score = round(
        100
        * (
            ew["sequencing"] * seq_score
            + ew["separation"] * sep_score
            + ew["knee"] * knee_score
            + ew["contact_extension"] * contact_score
            + ew["follow_through"] * follow_score
        )
    )
    efficiency_score = int(_clip100(efficiency_score))

    # ---- injury risk ----
    elbow_lo, elbow_hi = CONFIG["elbow_angle_range"]
    knee_r_lo, knee_r_hi = CONFIG["knee_flexion_range"]
    rs = CONFIG["risk_scale"]

    elbow_angle_c = metrics_at_contact.get("elbow_angle")
    shoulder_abd_c = metrics_at_contact.get("shoulder_abduction")
    wrist_ext_c = metrics_at_contact.get("wrist_extension")
    trunk_flex_c = metrics_at_contact.get("trunk_lateral_flexion")
    knee_flex_c = metrics_at_contact.get("knee_flexion")

    def _over_risk(value, lo, hi, scale):
        if value is None:
            return 0.0
        over = 0.0
        if lo is not None and value < lo:
            over = lo - value
        if hi is not None and value > hi:
            over = max(over, value - hi)
        return _clip01(over / scale) * 100.0

    elbow_angle_risk = _over_risk(elbow_angle_c, elbow_lo, elbow_hi, rs["elbow"])
    shoulder_risk_v = _over_risk(shoulder_abd_c, None, CONFIG["shoulder_abduction_max"], rs["shoulder"])
    wrist_risk_v = _over_risk(wrist_ext_c, None, CONFIG["wrist_extension_max"], rs["wrist"])
    trunk_risk_v = _over_risk(abs(trunk_flex_c) if trunk_flex_c is not None else None, None, CONFIG["trunk_lateral_flexion_max"], rs["lower_back"])
    knee_risk_v = _over_risk(knee_flex_c, knee_r_lo, knee_r_hi, rs["knee"])

    arm_share = force_distribution.get("arm", 0)
    arm_dominant_extra = _clip01(max(0.0, arm_share - CONFIG["arm_dominant_share"]) / 30.0) * 100.0

    risk_by_joint = {
        "elbow": round(_clip100(elbow_angle_risk * 0.7 + arm_dominant_extra * 0.3)),
        "shoulder": round(_clip100(shoulder_risk_v * 0.7 + arm_dominant_extra * 0.3)),
        "wrist": round(_clip100(wrist_risk_v * 0.9 + arm_dominant_extra * 0.1)),
        "lower_back": round(_clip100(trunk_risk_v)),
        "knee": round(_clip100(knee_risk_v)),
    }

    rw = CONFIG["risk_weights"]
    injury_risk_score = int(
        round(sum(risk_by_joint[j] * rw[j] for j in risk_by_joint))
    )
    injury_risk_score = int(_clip100(injury_risk_score))

    # ---- feedback ----
    feedback = _build_feedback(
        risk_by_joint=risk_by_joint,
        metrics_at_contact=metrics_at_contact,
        sequencing_ok=sequencing_ok,
        max_separation=max_separation,
        max_knee_flexion=max_knee_flexion,
        arm_share=arm_share,
        force_distribution=force_distribution,
    )

    trajectory = [
        {
            "t": round(f["t"], 3),
            "wrist_speed": f["metrics"].get("wrist_speed"),
            "hip_rotation_speed": f["metrics"].get("hip_rotation_speed"),
            "shoulder_rotation_speed": f["metrics"].get("shoulder_rotation_speed"),
            "elbow_angle": f["metrics"].get("elbow_angle"),
        }
        for f in _downsample(frames, CONFIG["trajectory_samples"])
    ]

    return {
        "id": swing_id,
        "t_start": round(t_start, 3),
        "t_contact": round(t_contact, 3),
        "t_end": round(t_end, 3),
        "efficiency_score": efficiency_score,
        "injury_risk_score": injury_risk_score,
        "risk_by_joint": risk_by_joint,
        "force_distribution": force_distribution,
        "ideal_distribution": dict(CONFIG["ideal_distribution"]),
        "metrics_at_contact": metrics_at_contact,
        "kinetic_chain": kinetic_chain,
        "feedback": feedback,
        "trajectory": trajectory,
    }


def _build_feedback(*, risk_by_joint, metrics_at_contact, sequencing_ok, max_separation, max_knee_flexion, arm_share, force_distribution) -> list[dict]:
    items = []
    danger = CONFIG["severity_danger"]
    warn = CONFIG["severity_warn"]

    def sev(score):
        if score >= danger:
            return "danger"
        if score >= warn:
            return "warn"
        return None

    elbow_angle_c = metrics_at_contact.get("elbow_angle")
    s = sev(risk_by_joint["elbow"])
    if s and elbow_angle_c is not None:
        if elbow_angle_c < 100:
            items.append({
                "severity": s, "joint": "elbow",
                "title": "Bent elbow at contact",
                "detail": f"Elbow was bent to {elbow_angle_c:.0f} deg at contact -- that loads the lateral epicondyle; aim for 140-160 deg.",
            })
        elif elbow_angle_c > 175:
            items.append({
                "severity": s, "joint": "elbow",
                "title": "Locked elbow at contact",
                "detail": f"Elbow was locked out to {elbow_angle_c:.0f} deg at contact -- a fully straight elbow transmits shock straight into the joint; keep a slight bend.",
            })

    s = sev(risk_by_joint["shoulder"])
    if s:
        items.append({
            "severity": s, "joint": "shoulder",
            "title": "High shoulder abduction",
            "detail": f"Shoulder abduction reached {metrics_at_contact.get('shoulder_abduction', 0):.0f} deg at contact -- staying above 90 deg repeatedly raises impingement risk.",
        })

    s = sev(risk_by_joint["wrist"])
    if s:
        items.append({
            "severity": s, "joint": "wrist",
            "title": "Excess wrist extension",
            "detail": f"Wrist extension was {metrics_at_contact.get('wrist_extension', 0):.0f} deg at contact -- flattening the wrist at contact reduces strain on the extensor tendons.",
        })

    s = sev(risk_by_joint["lower_back"])
    if s:
        items.append({
            "severity": s, "joint": "lower_back",
            "title": "Excess trunk lean",
            "detail": f"Trunk lateral flexion hit {metrics_at_contact.get('trunk_lateral_flexion', 0):.0f} deg -- lean this far sideways loads the lumbar spine; try to rotate more and lean less.",
        })

    s = sev(risk_by_joint["knee"])
    if s:
        kf = metrics_at_contact.get("knee_flexion")
        if kf is not None and kf < 10:
            items.append({
                "severity": s, "joint": "knee",
                "title": "Stiff-legged swing",
                "detail": f"Knees were nearly straight ({kf:.0f} deg flexion) through the swing -- bend the knees more to use your legs and take load off the upper body.",
            })
        else:
            items.append({
                "severity": s, "joint": "knee",
                "title": "Over-flexed knees",
                "detail": f"Knee flexion reached {kf:.0f} deg -- that is deeper than needed and can strain the knees; aim for 30-50 deg.",
            })

    if arm_share > CONFIG["arm_dominant_share"]:
        items.append({
            "severity": "warn" if arm_share <= 45 else "danger",
            "joint": "chain",
            "title": "Arm-dominant swing",
            "detail": f"The arm contributed about {arm_share:.0f}% of estimated swing energy -- hips and trunk are underused; drive more from the legs and hip rotation before the arm accelerates.",
        })

    if not sequencing_ok:
        items.append({
            "severity": "warn",
            "joint": "chain",
            "title": "Kinetic chain out of sequence",
            "detail": "Hips, shoulders and arm did not fire in a clean proximal-to-distal order -- work on rotating hips first, then shoulders, then let the arm follow.",
        })

    # Always include at least one "good" item.
    good_candidates = []
    if sequencing_ok:
        good_candidates.append({
            "severity": "good", "joint": "chain",
            "title": "Clean kinetic chain",
            "detail": "Hips led shoulders which led the arm -- that proximal-to-distal sequencing is exactly what generates racket speed efficiently.",
        })
    sep_lo, sep_hi = CONFIG["separation_target"]
    if sep_lo <= max_separation <= sep_hi:
        good_candidates.append({
            "severity": "good", "joint": "chain",
            "title": "Good hip-shoulder separation",
            "detail": f"Hip-shoulder separation reached {max_separation:.0f} deg during the load -- that's a solid coil for generating power.",
        })
    knee_lo, knee_hi = CONFIG["knee_flexion_target"]
    if knee_lo <= max_knee_flexion <= knee_hi:
        good_candidates.append({
            "severity": "good", "joint": "knee",
            "title": "Good knee bend",
            "detail": f"Knee flexion reached {max_knee_flexion:.0f} deg during preparation -- good use of the legs to load the swing.",
        })
    if elbow_angle_c is not None and 140 <= elbow_angle_c <= 170:
        good_candidates.append({
            "severity": "good", "joint": "elbow",
            "title": "Solid arm extension at contact",
            "detail": f"Elbow was extended to {elbow_angle_c:.0f} deg at contact -- a healthy extension range that spreads load away from the joint.",
        })
    if risk_by_joint["shoulder"] < warn:
        good_candidates.append({
            "severity": "good", "joint": "shoulder",
            "title": "Shoulder stayed in a safe range",
            "detail": "Shoulder abduction stayed under the impingement-risk threshold through contact.",
        })

    if good_candidates:
        items.append(good_candidates[0])
    else:
        items.append({
            "severity": "good", "joint": "chain",
            "title": "Swing completed",
            "detail": "You completed a full forehand motion through contact -- keep working on the specific points above to build on it.",
        })

    return items
