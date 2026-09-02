"""Exercises the real LiveSession -> Coach -> status-queue wiring that the
WebSocket sender drains, without needing a camera or a live swing."""
import sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server
from tests.test_coach import REPORT


def _drain(session, kinds, timeout=25.0):
    seen = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        seen.extend(session.pop_status())
        if all(any(m.get("type") == k for m in seen) for k in kinds):
            break
        time.sleep(0.05)
    return seen


def test_swing_produces_coach_messages_on_the_status_queue():
    session = server.LiveSession(camera="uid:NO_SUCH_DEVICE", model="lite", handedness="right",
                                fps=10, jpeg_quality=50, width=320, coach=True, coach_voice=False)
    try:
        assert session.coach is not None
        assert session.coach.submit(REPORT) is True
        seen = _drain(session, ("coach", "coach_spoken"))
    finally:
        session.stop()

    coach_msgs = [m for m in seen if m.get("type") == "coach"]
    spoken = [m for m in seen if m.get("type") == "coach_spoken"]
    assert len(coach_msgs) == 1
    assert len(spoken) == 1

    msg = coach_msgs[0]
    assert msg["swing_id"] == REPORT["id"]
    assert 1 <= len(msg["items"]) <= 2
    assert all(i["problem"] and i["fix"] for i in msg["items"])
    assert msg["text"] and len(msg["text"].split()) <= 56
    assert msg["source"] in ("cerebras", "local")


def test_coach_can_be_disabled():
    session = server.LiveSession(camera="uid:NO_SUCH_DEVICE", model="lite", handedness="right",
                                fps=10, jpeg_quality=50, width=320, coach=False)
    try:
        assert session.coach is None
    finally:
        session.stop()
