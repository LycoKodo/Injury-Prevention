import sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import coach


REPORT = {
    "id": 7, "efficiency_score": 46, "injury_risk_score": 37,
    "risk_by_joint": {"elbow": 62, "shoulder": 30, "wrist": 55, "lower_back": 10, "knee": 12},
    "force_distribution": {"legs": 9, "hips": 21, "trunk": 0, "shoulder": 33, "arm": 37},
    "metrics_at_contact": {"elbow_angle": 96, "shoulder_abduction": 88, "wrist_extension": 72,
                           "trunk_lateral_flexion": 4, "knee_flexion": 18, "hip_shoulder_separation": 6},
    "kinetic_chain": {"sequencing_ok": False, "lag_hip_to_shoulder_ms": 0, "lag_shoulder_to_arm_ms": -35},
    "feedback": [
        {"severity": "danger", "joint": "elbow", "title": "Bent elbow at contact",
         "detail": "Elbow was bent to 96 deg at contact -- that loads the lateral epicondyle."},
        {"severity": "warn", "joint": "wrist", "title": "Excess wrist extension",
         "detail": "Wrist extension was 72 deg at contact -- flatten the wrist."},
        {"severity": "warn", "joint": "knee", "title": "Stiff legs",
         "detail": "Knee flexion only 18 deg -- bend more."},
    ],
}


def test_local_items_returns_at_most_two_highest_severity_first():
    items = coach.local_items(REPORT)
    assert 1 <= len(items) <= coach.MAX_ITEMS
    assert items[0]["joint"] == "elbow"          # danger outranks warn
    assert all(it["problem"] and it["fix"] for it in items)


def test_good_swing_still_gets_a_line():
    items = coach.local_items({"id": 1, "efficiency_score": 88, "feedback": []})
    assert len(items) == 1
    assert items[0]["fix"]


def test_speech_fits_inside_the_thirty_second_budget():
    text = coach.items_to_speech(coach.local_items(REPORT))
    words = len(text.split())
    assert words <= coach.MAX_WORDS
    assert words / coach.WORDS_PER_SECOND < coach.MAX_SPEECH_SECONDS


def test_trim_to_words_caps_length():
    assert len(coach.trim_to_words(" ".join(["word"] * 500)).split()) <= coach.MAX_WORDS


def test_clean_expands_units_for_speech():
    assert "degrees" in coach._clean("bent to 96 deg at contact")
    assert "deg " not in coach._clean("bent to 96 deg at contact") + " "


def test_cerebras_returns_none_without_key(monkeypatch):
    monkeypatch.delenv("CEREBRAS_API_KEY", raising=False)
    assert coach.cerebras_items(REPORT) is None


def test_elevenlabs_returns_none_without_key(monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    assert coach.elevenlabs_mp3("hello") is None


def test_worker_drops_swings_while_busy(monkeypatch):
    """Real-time guarantee: a swing arriving mid-coaching is dropped, not queued."""
    monkeypatch.setattr(coach, "cerebras_items", lambda r, **k: None)
    seen = []
    c = coach.Coach(on_result=seen.append, speak=True)
    monkeypatch.setattr(c._speaker, "speak", lambda t: (time.sleep(0.6), "system")[1])
    try:
        assert c.submit(REPORT) is True
        time.sleep(0.15)
        dropped = [c.submit(REPORT) for _ in range(3)]
        assert not any(dropped)
        deadline = time.time() + 5
        while time.time() < deadline and not any(m["type"] == "coach_spoken" for m in seen):
            time.sleep(0.05)
    finally:
        c.stop()
    kinds = [m["type"] for m in seen]
    assert kinds.count("coach") == 1
    assert "coach_spoken" in kinds
    assert seen[0]["source"] == "local"
    assert len(seen[0]["items"]) <= coach.MAX_ITEMS
