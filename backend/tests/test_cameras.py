import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cameras


def test_kind_classification():
    assert cameras._kind_for("iPhone Camera", "AVCaptureDeviceTypeExternal") == "iphone"
    assert cameras._kind_for("Arona's iPad", "AVCaptureDeviceTypeExternal") == "iphone"
    assert cameras._kind_for("MacBook Pro Camera", "AVCaptureDeviceTypeBuiltInWideAngleCamera") == "builtin"
    assert cameras._kind_for("Logitech BRIO", "AVCaptureDeviceTypeExternal") == "external"


def test_list_cameras_shape():
    cams = cameras.list_cameras()
    assert isinstance(cams, list)
    for c in cams:
        assert set(c) == {"index", "source", "uid", "name", "kind", "connected"}
        assert isinstance(c["index"], int)
        assert c["kind"] in ("builtin", "iphone", "external")
        assert c["connected"] is True
        # source is either a positional index or a stable uid: reference
        assert c["source"] == str(c["index"]) or c["source"] == f"uid:{c['uid']}"


def test_open_source_resolves_uid_to_current_index(monkeypatch):
    monkeypatch.setattr(cameras, "list_cameras", lambda: [
        {"index": 0, "source": "uid:AAA", "uid": "AAA", "name": "Mac", "kind": "builtin", "connected": True},
        {"index": 1, "source": "uid:BBB", "uid": "BBB", "name": "iPhone", "kind": "iphone", "connected": True},
    ])
    assert cameras.resolve_uid("BBB") == 1
    assert cameras.resolve_uid("AAA") == 0
    assert cameras.resolve_uid("GONE") is None

    seen = {}

    class FakeCap:
        def isOpened(self):
            return True

        def set(self, *a):
            pass

    monkeypatch.setattr(cameras.cv2, "VideoCapture", lambda *a: (seen.update(arg=a[0] if a else None), FakeCap())[1])
    cameras.open_source("uid:BBB")
    assert seen["arg"] == 1


def test_open_source_unknown_uid_returns_unopened(monkeypatch):
    monkeypatch.setattr(cameras, "list_cameras", lambda: [])
    cap = cameras.open_source("uid:MISSING")
    assert not cap.isOpened()


def test_aspect_requests_are_4_3_and_16_9():
    w, h = cameras.ASPECT_REQUESTS["4:3"]
    assert abs(w / h - 4 / 3) < 0.01
    w, h = cameras.ASPECT_REQUESTS["16:9"]
    assert abs(w / h - 16 / 9) < 0.01


def test_open_source_accepts_urls_without_index_parsing(monkeypatch):
    seen = {}

    class FakeCap:
        def isOpened(self):
            return True

        def set(self, *a):
            seen.setdefault("set", []).append(a)

    def fake_videocapture(arg, *rest):
        seen["arg"] = arg
        return FakeCap()

    monkeypatch.setattr(cameras.cv2, "VideoCapture", fake_videocapture)
    cameras.open_source("rtsp://192.168.1.5:8554/live")
    assert seen["arg"] == "rtsp://192.168.1.5:8554/live"

    seen.clear()
    cameras.open_source("1", aspect="4:3")
    assert seen["arg"] == 1
