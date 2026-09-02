"""Camera enumeration. On macOS uses AVFoundation so Continuity Camera iPhones
show up with their real names; elsewhere falls back to probing indices."""
from __future__ import annotations

import sys

import cv2

MAX_CAMERA_PROBE = 4


def _kind_for(name: str, device_type: str) -> str:
    n = name.lower()
    if "iphone" in n or "ipad" in n or "Continuity" in device_type:
        return "iphone"
    if "BuiltIn" in device_type:
        return "builtin"
    return "external"


def _avfoundation_cameras() -> list[dict] | None:
    try:
        import AVFoundation as AV  # pyobjc-framework-AVFoundation
    except Exception:
        return None
    try:
        # OpenCV's AVFoundation backend indexes devices in the order of the
        # default video device list, which excludes Desk View virtual cameras.
        types = [
            "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            "AVCaptureDeviceTypeExternal",
            "AVCaptureDeviceTypeContinuityCamera",
        ]
        session = AV.AVCaptureDeviceDiscoverySession.discoverySessionWithDeviceTypes_mediaType_position_(
            types, "vide", 0
        )
        found = []
        for idx, dev in enumerate(session.devices()):
            name = str(dev.localizedName())
            dtype = str(dev.deviceType())
            if not bool(dev.isConnected()):
                # A Continuity Camera iPhone that has gone out of range still lingers
                # in some enumerations; offering it would only produce black frames.
                continue
            uid = str(dev.uniqueID())
            found.append({"index": idx, "source": f"uid:{uid}", "uid": uid, "name": name,
                          "kind": _kind_for(name, dtype), "connected": True})
        return found
    except Exception:
        return None


def _probe_cameras() -> list[dict]:
    found = []
    for idx in range(MAX_CAMERA_PROBE):
        cap = cv2.VideoCapture(idx)
        try:
            if cap.isOpened():
                ok, _ = cap.read()
                if ok:
                    found.append({"index": idx, "source": str(idx), "uid": None, "name": f"Camera {idx}",
                                  "kind": "builtin" if idx == 0 else "external", "connected": True})
        finally:
            cap.release()
    return found


def list_cameras() -> list[dict]:
    if sys.platform == "darwin":
        cams = _avfoundation_cameras()
        if cams:
            return cams
    return _probe_cameras()


# Requesting a 4:3 frame makes AVFoundation pick the sensor's full-height format
# (e.g. 1920x1440 on a Continuity Camera iPhone instead of a cropped 1920x1080).
# That extra vertical coverage is what lets a whole player fit in frame.
ASPECT_REQUESTS = {
    "4:3": (1920, 1440),
    "16:9": (1920, 1080),
}


def resolve_uid(uid: str) -> int | None:
    """Map a stable AVFoundation uniqueID to its CURRENT positional index.

    OpenCV addresses cameras by position in the device list, but that position
    shifts whenever a Continuity Camera iPhone connects or drops out. Resolving
    at open time keeps a saved camera choice pointing at the right device.
    """
    for cam in list_cameras():
        if cam.get("uid") == uid:
            return cam["index"]
    return None


def open_source(source: str | int, aspect: str = "4:3") -> cv2.VideoCapture:
    """Open a camera index ("0", 1), a "uid:<id>" device, or a stream URL."""
    s = str(source).strip()
    if s.startswith("uid:"):
        idx = resolve_uid(s[4:])
        if idx is None:
            return cv2.VideoCapture()  # not opened; caller reports the failure
        s = str(idx)
    if s.isdigit():
        idx = int(s)
        if sys.platform == "darwin":
            cap = cv2.VideoCapture(idx, cv2.CAP_AVFOUNDATION)
        else:
            cap = cv2.VideoCapture(idx)
        want = ASPECT_REQUESTS.get(aspect)
        # NB: do not gate this on cap.isOpened() — the AVFoundation backend reports
        # not-opened until the first read, so the guard silently skipped the request
        # and every camera fell back to its default 16:9 format.
        if want:
            try:
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, want[0])
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, want[1])
            except Exception:
                pass
        return cap
    cap = cv2.VideoCapture(s)
    try:
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # keep network streams low-latency
    except Exception:
        pass
    return cap


def center_stage_enabled() -> bool | None:
    """True if macOS Center Stage auto-framing is on. It pans and crops the
    image, which corrupts normalized landmark coordinates and speed estimates,
    so the app warns when it is active. None if it cannot be determined."""
    if sys.platform != "darwin":
        return None
    try:
        import AVFoundation as AV

        return bool(AV.AVCaptureDevice.isCenterStageEnabled())
    except Exception:
        return None
