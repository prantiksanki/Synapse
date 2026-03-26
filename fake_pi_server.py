"""
SYNAPSE Fake Pi Server
======================
Run this on your PC to test the Flutter app without real Raspberry Pi hardware.

SETUP:
    pip install python-socketio eventlet Pillow

RUN:
    python fake_pi_server.py

Then in App2/lib/config/app_config.dart change:
    hwSocketUrl = 'http://<YOUR_PC_IP>:5000'
where <YOUR_PC_IP> is your PC's local IP (e.g. 192.168.1.5).

Your phone and PC must be on the SAME WiFi network.
"""

import socketio
import eventlet
import eventlet.wsgi
import threading
import time
import io
import os

# Try to import PIL for generating test frames; falls back to a static JPEG
try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("[WARN] Pillow not installed — static test frame will be used.")
    print("       Install with: pip install Pillow")

sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet')
app = socketio.WSGIApp(sio)

# ── State ────────────────────────────────────────────────────────────────────
streaming_clients = set()
stream_threads = {}

# ── Helpers ──────────────────────────────────────────────────────────────────

def make_test_frame(label: str = "PI CAM", frame_num: int = 0) -> bytes:
    """Generate a 640x480 test JPEG with a frame counter."""
    if PIL_AVAILABLE:
        img = Image.new("RGB", (640, 480), color=(20, 20, 40))
        draw = ImageDraw.Draw(img)
        # Background gradient-like bars
        for i in range(0, 480, 40):
            color = (30 + i // 5, 20, 60 - i // 10)
            draw.rectangle([0, i, 640, i + 39], fill=color)
        # Center text
        draw.rectangle([160, 180, 480, 300], fill=(0, 0, 0))
        draw.text((170, 190), "SYNAPSE TEST SERVER", fill=(0, 200, 255))
        draw.text((170, 220), f"Frame: {frame_num}", fill=(255, 255, 255))
        draw.text((170, 250), label, fill=(100, 255, 100))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=65)
        return buf.getvalue()
    else:
        # Minimal valid 1x1 white JPEG
        return bytes([
            0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01,
            0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0xFF,0xDB,0x00,0x43,
            0x00,0x08,0x06,0x06,0x07,0x06,0x05,0x08,0x07,0x07,0x07,0x09,
            0x09,0x08,0x0A,0x0C,0x14,0x0D,0x0C,0x0B,0x0B,0x0C,0x19,0x12,
            0x13,0x0F,0x14,0x1D,0x1A,0x1F,0x1E,0x1D,0x1A,0x1C,0x1C,0x20,
            0x24,0x2E,0x27,0x20,0x22,0x2C,0x23,0x1C,0x1C,0x28,0x37,0x29,
            0x2C,0x30,0x31,0x34,0x34,0x34,0x1F,0x27,0x39,0x3D,0x38,0x32,
            0x3C,0x2E,0x33,0x34,0x32,0xFF,0xC0,0x00,0x0B,0x08,0x00,0x01,
            0x00,0x01,0x01,0x01,0x11,0x00,0xFF,0xC4,0x00,0x1F,0x00,0x00,
            0x01,0x05,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,
            0x09,0x0A,0x0B,0xFF,0xC4,0x00,0xB5,0x10,0x00,0x02,0x01,0x03,
            0x03,0x02,0x04,0x03,0x05,0x05,0x04,0x04,0x00,0x00,0x01,0x7D,
            0x01,0x02,0x03,0x00,0x04,0x11,0x05,0x12,0x21,0x31,0x41,0x06,
            0x13,0x51,0x61,0x07,0x22,0x71,0x14,0x32,0x81,0x91,0xA1,0x08,
            0x23,0x42,0xB1,0xC1,0x15,0x52,0xD1,0xF0,0x24,0x33,0x62,0x72,
            0x82,0x09,0x0A,0x16,0x17,0x18,0x19,0x1A,0x25,0x26,0x27,0x28,
            0x29,0x2A,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x43,0x44,0x45,
            0x46,0x47,0x48,0x49,0x4A,0x53,0x54,0x55,0x56,0x57,0x58,0x59,
            0x5A,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x73,0x74,0x75,
            0x76,0x77,0x78,0x79,0x7A,0x83,0x84,0x85,0x86,0x87,0x88,0x89,
            0x8A,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0xA2,0xA3,0xA4,
            0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,
            0xB8,0xB9,0xBA,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xCA,
            0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,0xE1,0xE2,0xE3,
            0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xF1,0xF2,0xF3,0xF4,0xF5,
            0xF6,0xF7,0xF8,0xF9,0xFA,0xFF,0xDA,0x00,0x08,0x01,0x01,0x00,
            0x00,0x3F,0x00,0xFB,0xD2,0x8A,0x28,0x03,0xFF,0xD9
        ])


def stream_frames(sid: str, fps: int, quality: int):
    """Background thread: push JPEG frames to a connected client."""
    frame_num = 0
    interval = 1.0 / max(fps, 1)
    print(f"[STREAM] Started streaming to {sid} at {fps}fps")
    while sid in streaming_clients:
        try:
            frame_bytes = make_test_frame(f"fps={fps} q={quality}", frame_num)
            sio.emit('frame', list(frame_bytes), to=sid)
            frame_num += 1
        except Exception as e:
            print(f"[STREAM] Error sending frame: {e}")
            break
        time.sleep(interval)
    print(f"[STREAM] Stopped streaming to {sid}")


# ── Socket.IO Events ─────────────────────────────────────────────────────────

@sio.event
def connect(sid, environ):
    remote_addr = environ.get('REMOTE_ADDR', 'unknown')
    x_forwarded = environ.get('HTTP_X_FORWARDED_FOR')
    address = x_forwarded or remote_addr or 'unknown'
    print(f"\n[+] Incoming connection attempt: sid={sid}, from={address}")

    # Optional: whitelist clients in future:
    # if not allowed_client(address):
    #     print(f"[-] Rejecting client {address}")
    #     return False

    print(f"[+] Phone connected: {sid} ({address})")
    # Send hardware info immediately
    sio.emit('hw_info', {
        'device': 'SYNAPSE-HW',
        'version': '1.0-fake',
        'ip': '192.168.1.100',
        'camera': 'FakeCam 640x480',
        'camera_ok': True,
        'mic_ok': True,
        'speaker_ok': True,
    }, to=sid)
    print(f"    → sent hw_info")


@sio.event
def disconnect(sid):
    print(f"[-] Phone disconnected: {sid}")
    streaming_clients.discard(sid)


@sio.event
def start_stream(sid, data):
    fps = data.get('fps', 30) if isinstance(data, dict) else 30
    quality = data.get('quality', 65) if isinstance(data, dict) else 65
    print(f"[>] start_stream from {sid}: fps={fps} quality={quality}")
    streaming_clients.add(sid)
    t = threading.Thread(target=stream_frames, args=(sid, fps, quality), daemon=True)
    stream_threads[sid] = t
    t.start()


@sio.event
def stop_stream(sid, data=None):
    print(f"[>] stop_stream from {sid}")
    streaming_clients.discard(sid)


@sio.event
def start_mic(sid, data=None):
    print(f"[>] start_mic from {sid}")


@sio.event
def stop_mic(sid, data=None):
    print(f"[>] stop_mic from {sid}")


@sio.event
def speak(sid, data):
    text = data.get('text', '') if isinstance(data, dict) else str(data)
    print(f"[SPEAK] {text}")


@sio.event
def update_screen(sid, data):
    top = data.get('top', '') if isinstance(data, dict) else ''
    mid = data.get('mid', '') if isinstance(data, dict) else ''
    bot = data.get('bot', '') if isinstance(data, dict) else ''
    print(f"[LCD]  top: {top!r}")
    print(f"       mid: {mid!r}")
    print(f"       bot: {bot!r}")


@sio.event
def ping_hw(sid, data=None):
    sio.emit('pong_hw', {}, to=sid)


# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    import socket

    # Print local IP so you know what to put in app_config.dart
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    print("=" * 60)
    print("  SYNAPSE Fake Pi Server")
    print("=" * 60)
    print(f"  Local IP  : {local_ip}")
    print(f"  Port      : 5000")
    print()
    print("  In App2/lib/config/app_config.dart set:")
    print(f"    hwSocketUrl = 'http://{local_ip}:5000'")
    print()
    print("  Make sure your phone is on the SAME WiFi as this PC.")
    print("=" * 60)
    print()

    eventlet.wsgi.server(eventlet.listen(('0.0.0.0', 5000)), app)