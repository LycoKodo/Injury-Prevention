import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import biomechanics as bio


def test_angle_3pt_right_angle():
    a = [1, 0, 0]
    b = [0, 0, 0]
    c = [0, 1, 0]
    assert math.isclose(bio.angle_3pt(a, b, c), 90.0, abs_tol=1e-6)


def test_angle_3pt_straight():
    a = [-1, 0, 0]
    b = [0, 0, 0]
    c = [1, 0, 0]
    assert math.isclose(bio.angle_3pt(a, b, c), 180.0, abs_tol=1e-6)


def test_angle_3pt_zero():
    a = [1, 0, 0]
    b = [0, 0, 0]
    c = [1, 0, 0]
    assert math.isclose(bio.angle_3pt(a, b, c), 0.0, abs_tol=1e-6)


def test_line_angle_deg_horizontal():
    assert math.isclose(bio.line_angle_deg([0, 0], [1, 0]), 0.0, abs_tol=1e-6)


def test_line_angle_deg_vertical():
    assert math.isclose(bio.line_angle_deg([0, 0], [0, 1]), 90.0, abs_tol=1e-6)


def test_line_angle_deg_mod180():
    # opposite direction line -> same mod-180 angle as horizontal
    assert math.isclose(bio.line_angle_deg([0, 0], [-1, 0]), 0.0, abs_tol=1e-6)


def test_angle_diff_mod180_simple():
    assert math.isclose(bio.angle_diff_mod180(100, 90), 10.0, abs_tol=1e-6)


def test_angle_diff_mod180_wrap():
    # 170 vs 10: shortest path is -20 (170 -> 190==10 is 20 away the other way)
    assert math.isclose(bio.angle_diff_mod180(170, 10), -20.0, abs_tol=1e-6)


def _neutral_landmarks():
    """A person standing upright, facing the camera, arms straight at sides."""
    lm = [[0.5, 0.5, 0.0, 1.0] for _ in range(33)]
    lm[bio.L_SHOULDER] = [0.40, 0.30, 0.0, 1.0]
    lm[bio.R_SHOULDER] = [0.60, 0.30, 0.0, 1.0]
    lm[bio.L_ELBOW] = [0.38, 0.45, 0.0, 1.0]
    lm[bio.R_ELBOW] = [0.62, 0.45, 0.0, 1.0]
    lm[bio.L_WRIST] = [0.37, 0.60, 0.0, 1.0]
    lm[bio.R_WRIST] = [0.63, 0.60, 0.0, 1.0]
    lm[bio.L_INDEX] = [0.368, 0.63, 0.0, 1.0]
    lm[bio.R_INDEX] = [0.632, 0.63, 0.0, 1.0]
    lm[bio.L_HIP] = [0.42, 0.55, 0.0, 1.0]
    lm[bio.R_HIP] = [0.58, 0.55, 0.0, 1.0]
    lm[bio.L_KNEE] = [0.42, 0.75, 0.0, 1.0]
    lm[bio.R_KNEE] = [0.58, 0.75, 0.0, 1.0]
    lm[bio.L_ANKLE] = [0.42, 0.95, 0.0, 1.0]
    lm[bio.R_ANKLE] = [0.58, 0.95, 0.0, 1.0]
    return lm


def test_live_metrics_neutral_pose():
    computer = bio.LiveMetricsComputer(handedness="right")
    metrics = computer.update(_neutral_landmarks(), 0.0)

    assert metrics["handedness"] == "right"
    assert math.isclose(metrics["elbow_angle"], 180.0, abs_tol=5.0)
    assert math.isclose(metrics["knee_flexion"], 0.0, abs_tol=2.0)
    assert math.isclose(metrics["hip_shoulder_separation"], 0.0, abs_tol=2.0)
    assert abs(metrics["trunk_lateral_flexion"]) < 2.0
    assert abs(metrics["wrist_extension"]) < 5.0


def test_live_metrics_none_landmarks_returns_nulls():
    computer = bio.LiveMetricsComputer(handedness="right")
    computer.update(_neutral_landmarks(), 0.0)
    metrics = computer.update(None, 0.1)
    assert metrics["elbow_angle"] is None
    assert metrics["wrist_speed"] is None
    assert metrics["handedness"] == "right"


def test_knee_flexion_bent():
    lm = _neutral_landmarks()
    # bend both knees forward (in x) which reduces the hip-knee-ankle angle
    lm[bio.L_KNEE] = [0.50, 0.72, 0.0, 1.0]
    lm[bio.R_KNEE] = [0.50, 0.72, 0.0, 1.0]
    computer = bio.LiveMetricsComputer(handedness="right")
    metrics = computer.update(lm, 0.0)
    assert metrics["knee_flexion"] > 15.0


def test_wrist_speed_from_motion():
    computer = bio.LiveMetricsComputer(handedness="right")
    lm1 = _neutral_landmarks()
    computer.update(lm1, 0.0)
    lm2 = _neutral_landmarks()
    lm2[bio.R_WRIST] = [0.90, 0.60, 0.0, 1.0]  # big jump to the right
    metrics = computer.update(lm2, 0.1)
    assert metrics["wrist_speed"] > 0.0
