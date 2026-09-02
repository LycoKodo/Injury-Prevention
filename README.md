# Tennis Form Coach — local CV forehand analysis

Prototype that watches a tennis player through a webcam (or a video file), estimates their pose with a
**fully local** MediaPipe Pose Landmarker model, and scores each forehand for

- **swing efficiency** — how well the kinetic chain (legs → hips → trunk → shoulder → arm) is used, and
- **injury risk** — elbow, shoulder, wrist, lower back and knee loading proxies,

with an estimated *force distribution* across the chain and coach-style feedback.

```
backend/   Python 3.13 · FastAPI · MediaPipe 0.10.35 · OpenCV      (all inference on-device)
app/       Flutter desktop client (macOS target + web fallback)
docs/      PROTOCOL.md — the JSON contract between the two
```

## Run

```sh
# 1. backend (first time: python3.13 -m venv backend/.venv && backend/.venv/bin/pip install -r backend/requirements.txt)
backend/run.sh                      # serves http://127.0.0.1:8765

# 2. app
cd app && flutter run -d macos      # needs full Xcode installed
cd app && flutter run -d chrome     # fallback without Xcode
```

Pose model files live in `backend/models/*.task` (downloaded from the MediaPipe model zoo; not committed).

## Talking coach

After each swing the coach speaks one or two cues, each a **problem** and a **fix**, through the Mac's
speakers. It is deliberately limited:

- **At most two cues.** A player mid-rally cannot act on more.
- **Under 30 seconds.** Enforced by a word budget, with playback killed as a backstop. Worst case
  measured at the cap is 17 seconds.
- **Swings that land while it is still talking are skipped, not queued.** Late advice is worse than
  none, so the app tells you the swing was skipped instead.

It degrades instead of failing. Text comes from Cerebras when the key works, otherwise from local
rules over the same swing metrics. Speech comes from ElevenLabs when the key works, otherwise the
macOS system voice. Configure keys in `backend/.env`, which is gitignored:

```sh
CEREBRAS_API_KEY=...
ELEVENLABS_API_KEY=...
# optional
CEREBRAS_MODEL=gpt-oss-120b
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
ELEVENLABS_MODEL=eleven_flash_v2_5
```

Turn it off per session with `coach=0`, or keep the text and silence the voice with `coach_voice=0`.

## Using an iPhone as the camera

The built-in MacBook camera is narrow, so a whole player rarely fits in frame. Three ways to use an
iPhone instead, best-effort first:

**1. Continuity Camera — no setup, works now.** Unlock the iPhone and mount it in landscape near the
Mac. It appears in the camera picker by name. Both devices need the same Apple Account with Wi-Fi and
Bluetooth on. Verified here at 1920x1440.

> Turn **Center Stage off** (Control Centre > Video Effects). Its auto-panning crops and moves the
> frame, which corrupts the normalized landmark coordinates the speed and angle estimates are built on.

**2. True ultra-wide (0.5x) — needs a streaming app.** Continuity Camera only exposes the iPhone's main
wide lens; there is no public API to select the ultra-wide. To get 0.5x, use an iPhone app that can pick
the ultra-wide lens and publish an RTSP or HTTP stream, then paste that URL into "Stream URL…" in the
camera picker. The backend accepts any URL OpenCV can open.

**3. Recorded clips — widest and highest quality.** Film at 0.5x in the iPhone Camera app and drop the
file into the Analyze Video screen. No streaming latency, full sensor resolution.

The `aspect` control defaults to **4:3**, which requests the sensor's full-height format. On the iPhone
that is 1920x1440 rather than a cropped 1920x1080 — a third more vertical coverage, which is what lets a
whole player fit. Switch to 16:9 only if you want a wider-than-tall frame.

## Caveats
- Force numbers are estimates derived from 2D joint kinematics, not measured ground-reaction forces.
- Side-on camera (perpendicular to the baseline) gives the most reliable elbow/knee angles; a front view gives better hip–shoulder separation.
- On a network that intercepts TLS, Python cannot verify certificates against its bundled store. The backend exports the macOS keychain roots to `backend/.cache/macos-roots.pem` and uses those, so API calls work without disabling verification.
- Continuity Camera sends black frames while the iPhone is asleep or face-down. The app warns when it detects this.
