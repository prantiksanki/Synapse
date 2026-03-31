#!/usr/bin/env python3
"""
SYNAPSE Pi4 - Raw I/O Server
Just pipes camera + mic to phone. Phone does everything else.

Install:
    pip3 install python-socketio eventlet opencv-python pyaudio

Run:
    python3 server.py
"""

import socketio
import eventlet
import eventlet.wsgi
import cv2
import pyaudio
import threading
import subprocess
import logging
import time

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger()

# ── CONFIG ───────────────────────────────────
PORT         = 5000
CAMERA_INDEX = 0          # /dev/video0
MIC_CARD     = 3          # from: arecord -l  → find your webcam mic card number
MIC_DEVICE   = 0
MIC_RATE     = 16000
MIC_CHUNK    = 1024       # samples
# ─────────────────────────────────────────────

sio = socketio.Server(
    cors_allowed_origins="*",
    async_mode="eventlet",
    # FIX: Flutter app uses websocket-only transport — allow both so the
    # EIO handshake (polling) can complete before upgrading to websocket.
    # Do NOT restrict to websocket-only here; let the client negotiate.
    logger=False,
    engineio_logger=False,
)
app = socketio.WSGIApp(sio)

_cam_running = False
_mic_running = False
_pa = pyaudio.PyAudio()


# ── CONNECT / DISCONNECT ──────────────────────

@sio.event
def connect(sid, environ):
    log.info(f"Phone connected: {sid}")
    sio.emit("hw_info", {
        "device": "SYNAPSE-HW",
        "version": "1.0",
        "ip": "192.168.4.1",  # Pi hotspot gateway IP
        "camera": "Lenovo 300 FHD",
        "camera_ok": True,
        "mic_ok": True,
        "speaker_ok": True,
    }, to=sid)

@sio.event
def disconnect(sid):
    global _cam_running, _mic_running
    log.info(f"Phone disconnected: {sid}")
    _cam_running = False
    _mic_running = False


# ── CAMERA ────────────────────────────────────

@sio.event
def start_stream(sid, data=None):
    global _cam_running
    data = data or {}
    fps     = int(data.get("fps", 30))
    quality = int(data.get("quality", 65))
    if _cam_running:
        return
    _cam_running = True
    threading.Thread(target=_cam_loop, args=(sid, fps, quality), daemon=True).start()
    log.info(f"Camera started fps={fps} quality={quality}")

@sio.event
def stop_stream(sid, data=None):
    global _cam_running
    _cam_running = False
    log.info("Camera stopped")

def _cam_loop(sid, fps, quality):
    global _cam_running
    cap = cv2.VideoCapture(CAMERA_INDEX, cv2.CAP_V4L2)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, fps)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        log.error("Cannot open camera")
        sio.emit("hw_error", {"source": "camera", "msg": "Cannot open /dev/video0"}, to=sid)
        _cam_running = False
        return

    encode_params = [cv2.IMWRITE_JPEG_QUALITY, quality]
    interval = 1.0 / fps

    while _cam_running:
        t = time.monotonic()
        ret, frame = cap.read()
        if not ret:
            eventlet.sleep(0.05)
            continue
        ok, buf = cv2.imencode(".jpg", frame, encode_params)
        if ok:
            sio.emit("frame", buf.tobytes(), to=sid)
        elapsed = time.monotonic() - t
        eventlet.sleep(max(0, interval - elapsed))

    cap.release()
    log.info("Camera thread done")


# ── MIC ───────────────────────────────────────

@sio.event
def start_mic(sid, data=None):
    global _mic_running
    if _mic_running:
        return
    _mic_running = True
    threading.Thread(target=_mic_loop, args=(sid,), daemon=True).start()
    log.info("Mic started")

@sio.event
def stop_mic(sid, data=None):
    global _mic_running
    _mic_running = False
    log.info("Mic stopped")

def _find_mic():
    for i in range(_pa.get_device_count()):
        info = _pa.get_device_info_by_index(i)
        if info["maxInputChannels"] >= 1 and f"hw:{MIC_CARD}" in info["name"]:
            return i
    try:
        return _pa.get_default_input_device_info()["index"]
    except Exception:
        return None

def _mic_loop(sid):
    global _mic_running
    dev = _find_mic()
    if dev is None:
        log.error("No mic found — check MIC_CARD in config")
        sio.emit("hw_error", {"source": "mic", "msg": "No mic device found"}, to=sid)
        _mic_running = False
        return

    stream = _pa.open(
        format=pyaudio.paInt16, channels=1, rate=MIC_RATE,
        input=True, input_device_index=dev, frames_per_buffer=MIC_CHUNK,
    )

    while _mic_running:
        try:
            pcm = stream.read(MIC_CHUNK, exception_on_overflow=False)
            sio.emit("audio", pcm, to=sid)
            eventlet.sleep(0)
        except OSError:
            eventlet.sleep(0.02)

    stream.stop_stream()
    stream.close()
    log.info("Mic thread done")


# ── PHONE → PI COMMANDS ───────────────────────

@sio.event
def speak(sid, data):
    text = data.get("text", "")
    log.info(f"speak: {text}")
    threading.Thread(target=lambda: subprocess.run(["espeak", text]), daemon=True).start()

@sio.event
def update_screen(sid, data):
    log.info(f"LCD: {data.get('top')} | {data.get('mid')} | {data.get('bot')}")

@sio.event
def ping_hw(sid, data=None):
    sio.emit("pong_hw", {}, to=sid)


# ── MAIN ──────────────────────────────────────

if __name__ == "__main__":
    log.info(f"SYNAPSE Pi server starting on 0.0.0.0:{PORT}")
    log.info("Tip: run 'arecord -l' to find your mic card number")
    eventlet.wsgi.server(
        eventlet.listen(("0.0.0.0", PORT)),
        app,
        log_output=False,
    )
