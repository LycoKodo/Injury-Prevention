# Tennis Form Coach -- Backend

Local-only Python backend. Runs MediaPipe Pose Landmarker fully on-device and
exposes a REST + WebSocket API at `http://127.0.0.1:8765` for the Flutter
client. No video, images, or pose data ever leave the machine -- all
inference happens locally in this process.

See `../docs/PROTOCOL.md` for the full wire contract (message shapes, field
names, scoring intent). This README covers only how to run and what's where.

## Running

```sh
./run.sh
```

This activates the existing virtualenv at `.venv` and starts uvicorn on
`127.0.0.1:8765`. The venv and pose models (`models/pose_landmarker_lite.task`,
`models/pose_landmarker_heavy.task`) must already be present (see
`requirements.txt`); this script does not install anything.

On first live-camera use, macOS will prompt for camera permission for the
terminal/app running the process.

## Endpoints

- `GET /health` -- `{"ok": true, "model": "lite", "version": "1"}`
- `GET /cameras` -- probes camera indices 0-3, returns the ones that open
  successfully: `{"cameras": [{"index": 0, "name": "Camera 0"}, ...]}`
- `GET /frame.jpg` -- latest raw JPEG frame from whatever live session is
  running (debug only; 404 if no live session has produced a frame yet)
- `POST /analyze` -- multipart form: `file` (mp4/mov), optional
  `handedness=right|left|auto` (default `auto`), `model=lite|heavy` (default
  `lite`). Runs the full video through pose + biomechanics + swing detection
  + scoring and returns an `AnalysisResult` (see PROTOCOL.md).
- `WS /ws/live?camera=0&model=lite&handedness=auto&fps=20&jpeg_quality=60&width=640`
  -- streams `frame`/`swing`/`status`/`error` JSON messages. Accepts
  `{"type":"set","handedness":"right"}` and `{"type":"reset"}` from the
  client. See PROTOCOL.md for message shapes.

## Code layout

- `pose_engine.py` -- thin wrapper around `mediapipe.tasks.python.vision.PoseLandmarker`
  (VIDEO running mode, lite/heavy model selection, monotonic timestamps).
- `biomechanics.py` -- pure-numpy geometry (`angle_3pt`, line-angle helpers)
  and `LiveMetricsComputer`, a stateful per-stream smoother that turns 33
  landmarks + a timestamp into a `LiveMetrics` dict each frame (elbow angle,
  hip-shoulder separation, wrist speed, auto handedness detection, etc).
- `swing_detector.py` -- `SwingDetector`, a state machine
  (idle -> preparation -> forward_swing -> contact -> follow_through -> idle)
  that watches the metrics stream, buffers ~4s of frames, and emits a
  `SwingReport` (via `scoring.py`) when a swing completes. Thresholds are
  constants at the top of the file.
- `scoring.py` -- pure function `build_swing_report(...)` that turns a
  buffered swing's frames into kinetic-chain sequencing, an estimated
  force distribution, efficiency/injury-risk scores, per-joint risk, and
  coach-style feedback strings. All thresholds/weights live in the `CONFIG`
  dict at the top of the file.
- `server.py` -- FastAPI app: REST endpoints, the `/ws/live` websocket (a
  background thread per connection captures + runs pose + feeds the
  detector; the async side throttles sends to the requested fps and drops
  frames rather than buffering), and `/analyze`'s offline video pipeline.
- `run.sh` -- convenience launcher.
- `tests/` -- pytest suite (`test_biomechanics.py`, `test_swing.py`).

## Tests

```sh
.venv/bin/pip install pytest   # already installed if you followed setup
.venv/bin/python -m pytest -q
```

`test_swing.py` builds synthetic landmark sequences (a well-sequenced
forehand and a deliberately arm-only, stiff-legged, bent-elbow one) and
exercises the full `LiveMetricsComputer` -> `SwingDetector` -> `scoring`
pipeline end to end.

## Notes / known limitations

- Force distribution and the injury-risk model are estimates derived from
  2D image-plane kinematics (peak angular velocities as energy proxies),
  not a real inverse-dynamics simulation -- the app should label them
  "estimated", per PROTOCOL.md.
- `hip_shoulder_separation` and rotation speeds are image-plane proxies
  (no depth/camera calibration), as specified in PROTOCOL.md.
