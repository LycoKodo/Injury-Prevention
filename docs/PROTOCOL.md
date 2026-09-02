# Tennis Form Coach — Backend/App Contract (v1)

Local-only system. Python backend runs MediaPipe Pose Landmarker (33 landmarks) fully on-device
and exposes it at `http://127.0.0.1:8765`. The Flutter app is a pure client; it never runs the model.

## Coordinate conventions
- `landmarks`: 33 entries, each `[x, y, z, visibility]`; `x,y` normalized to image width/height (0..1, origin top-left).
- `world_landmarks` (optional, swing reports only): metres, hip-centred, MediaPipe world coords.
- Landmark indices follow MediaPipe: 11 L shoulder, 12 R shoulder, 13 L elbow, 14 R elbow, 15 L wrist, 16 R wrist,
  23 L hip, 24 R hip, 25 L knee, 26 R knee, 27 L ankle, 28 R ankle.
- Angles in degrees. Times in seconds since stream/video start. Speeds in normalized-units/second (image) unless `_mps` suffix.

## REST
- `GET /health` -> `{"ok": true, "model": "lite"|"heavy", "version": "1"}`
- `GET /cameras` -> `{"cameras": [{"index": 0, "source": "uid:6C70...", "uid": "6C70...", "name": "MacBook Pro Camera", "kind": "builtin", "connected": true}]}`
  `kind` is `builtin` | `iphone` | `external`. On macOS names come from AVFoundation, so a Continuity
  Camera iPhone appears by its real name. Disconnected devices are omitted.
  `source` is an opaque string the client sends straight back to the server. On macOS it is
  `uid:<AVFoundation uniqueID>`, which the server resolves to the current positional index at open
  time — camera indices shift whenever an iPhone connects or drops out, so a saved index would
  silently point at the wrong device. Clients must treat `source` as opaque and never parse it.
- `POST /analyze` multipart form: `file` (mp4/mov), optional `handedness=right|left|auto`, `model=lite|heavy`
  -> `AnalysisResult`
- `GET /frame.jpg` -> latest live frame (debug only)

## WebSocket `GET /ws/live?camera=0&model=lite&handedness=auto&aspect=4:3&coach=1&coach_voice=1&fps=20&jpeg_quality=60&width=640`
- `coach=0` disables the talking coach entirely; `coach_voice=0` keeps the written cues but stays silent.
- `camera` is a device index as a string, OR pass `source` instead with a stream URL
  (`rtsp://...`, `http://.../video`) to use a phone streaming app as the camera.
- `aspect` is `4:3` (default) or `16:9`. 4:3 requests the sensor's full-height format, which on a
  Continuity Camera iPhone yields 1920x1440 instead of a cropped 1920x1080 — more vertical coverage
  so a whole player fits in frame. It does not change the normalized coordinate convention.
Server pushes JSON text messages. Client may send `{"type":"set","handedness":"right"}` or `{"type":"reset"}`.

```jsonc
// every processed frame
{ "type": "frame", "t": 12.345, "w": 640, "h": 480, "fps": 19.2,
  "jpeg": "<base64 JPEG of the raw frame, no overlay>",
  "landmarks": [[x,y,z,vis], ... 33] | null,
  "phase": "idle" | "preparation" | "forward_swing" | "contact" | "follow_through",
  "metrics": LiveMetrics }

// once per detected forehand
{ "type": "swing", "swing": SwingReport }

// after each detected swing, when the coach is enabled (coach=1, default)
{ "type": "coach", "swing_id": 3, "source": "cerebras" | "local",
  "items": [ { "problem": "Your elbow collapsed at contact.", "fix": "Drive through the ball with a firmer arm." } ],
  "text": "the full spoken line", "voice": "pending" | "off", "generate_ms": 240 }
{ "type": "coach_spoken", "swing_id": 3, "voice": "elevenlabs" | "system" | "off" | "none", "total_ms": 13400 }
// sent instead of "coach" when a swing lands while the previous one is still being coached
{ "type": "coach_skipped", "swing_id": 4 }

// informational
{ "type": "status", "message": "Camera opened (1920x1440)", "model": "lite", "handedness": "right", "camera": "1" }
// further status messages may arrive mid-stream, e.g. a black-frame warning (sleeping iPhone)
// or a Center Stage warning. Clients should display the latest one, not only the first.
{ "type": "error", "message": "..." }
```

### LiveMetrics (all may be null when no pose)
```jsonc
{ "elbow_angle": 145.0,             // hitting arm, 180 = straight
  "shoulder_abduction": 62.0,       // hitting arm upper-arm vs torso
  "hip_shoulder_separation": 28.0,  // X-factor: shoulder line vs hip line rotation (deg, image-plane proxy)
  "knee_flexion": 35.0,             // mean of both knees, 0 = straight
  "trunk_lateral_flexion": 8.0,     // torso tilt from vertical, signed (+ toward hitting side)
  "wrist_extension": 20.0,          // wrist angle deviation proxy from forearm line
  "wrist_speed": 1.8,               // hitting wrist speed, normalized units/s
  "hip_rotation_speed": 120.0,      // deg/s
  "shoulder_rotation_speed": 180.0, // deg/s
  "handedness": "right" }
```

### SwingReport
```jsonc
{ "id": 1, "t_start": 10.1, "t_contact": 10.6, "t_end": 11.2,
  "efficiency_score": 74,           // 0..100, higher = better kinetic-chain usage
  "injury_risk_score": 31,          // 0..100, higher = riskier
  "risk_by_joint": { "elbow": 40, "shoulder": 25, "wrist": 20, "lower_back": 35, "knee": 10 },
  "force_distribution": { "legs": 18, "hips": 22, "trunk": 20, "shoulder": 22, "arm": 18 }, // % of estimated swing energy, sums to 100
  "ideal_distribution": { "legs": 20, "hips": 25, "trunk": 20, "shoulder": 20, "arm": 15 },
  "metrics_at_contact": LiveMetrics,
  "kinetic_chain": { "hip_peak_t": 10.45, "shoulder_peak_t": 10.52, "arm_peak_t": 10.58,
                     "sequencing_ok": true, "lag_hip_to_shoulder_ms": 70, "lag_shoulder_to_arm_ms": 60 },
  "feedback": [ { "severity": "good"|"warn"|"danger", "joint": "elbow"|"shoulder"|"wrist"|"lower_back"|"knee"|"chain",
                  "title": "Arm-dominant swing", "detail": "Hips contributed only 9%..." } ],
  "trajectory": [ { "t": 10.1, "wrist_speed": 0.2, "hip_rotation_speed": 10, "shoulder_rotation_speed": 12, "elbow_angle": 150 }, ... ] // ~30 samples
}
```

### AnalysisResult (`POST /analyze`)
```jsonc
{ "duration": 34.2, "fps": 30, "handedness": "right", "swing_count": 6,
  "swings": [SwingReport, ...],
  "summary": { "avg_efficiency": 70, "avg_injury_risk": 33, "risk_by_joint": {...}, "force_distribution": {...},
               "top_feedback": [Feedback, ...] },
  "keyframes": { "<swing_id>": "<base64 JPEG at contact, with skeleton drawn>" } }
```

## Talking coach
At most TWO cues per swing, each a `problem` plus a `fix`, because a player mid-session cannot act
on more than that. The whole spoken line is capped to a word budget that keeps it under 30 seconds,
and playback is killed if it ever runs past that.

The coach is best-effort at every layer, and never blocks or delays the live stream:
- Text comes from Cerebras when reachable, otherwise from local rules over the same swing metrics.
- Speech comes from ElevenLabs when reachable, otherwise the macOS system voice.
- A swing arriving while the previous one is still being coached is DROPPED, not queued, because
  late advice is worse than none. The client is told via `coach_skipped`.

Keys live in `backend/.env` (gitignored): `CEREBRAS_API_KEY`, `ELEVENLABS_API_KEY`, and optionally
`CEREBRAS_MODEL`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL`.

## Scoring intent (backend implements; app only displays)
- Efficiency: proximal-to-distal sequencing (hips peak before shoulders before arm), hip-shoulder separation at start of forward swing (target 30-45 deg), knee flexion in preparation (target 30-50 deg), contact in front of body, follow-through length.
- Injury risk (tennis elbow, shoulder impingement, wrist, lumbar, knee): arm-dominant swing (arm share > 30%), elbow angle < 100 deg or > 175 deg at contact, shoulder abduction > 90 at contact, wrist extension > 30 deg at contact, trunk lateral flexion > 20 deg, knee valgus / knee flexion < 10 deg (stiff legs) or > 70.
- All force numbers are *estimates from 2D kinematics*, and the UI must label them "estimated".
