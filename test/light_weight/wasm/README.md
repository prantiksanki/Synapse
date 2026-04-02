# WASM Real-Time Letter Detection (from `model.tflite`)

This folder lets you run your lightweight letters model in-browser using:

- MediaPipe hand landmarks (`hand_landmarker.task`)
- TFLite runtime in WASM (`@tensorflow/tfjs-tflite`)

If browser-side TFLite WASM is blocked on your network, it automatically
falls back to `ws_bridge.py` server-side inference (same `model.tflite`).

## 1) No conversion required

This web runner now reads these files directly:

- `test/light_weight/model.tflite`
- `test/light_weight/labels.txt`
- `test/light_weight/normalization.json`
- `test/hand_landmarker.task`

## 2) Run the web app

Serve from `test` so the page can also load `test/hand_landmarker.task`.

```powershell
cd test
python -m http.server 8080
```

Open in browser:

`http://127.0.0.1:8080/light_weight/wasm/web/`

## 3) Optional: stream predictions to your app/backend

In the UI, set a WebSocket URL (example):

`ws://127.0.0.1:8787/ws/sign`

Then click **Connect WS**.  
Each frame prediction is sent as JSON:

```json
{
  "event": "prediction",
  "label": "A",
  "confidence": 0.92,
  "class_index": 0,
  "timestamp_ms": 1710000000000,
  "hands": 1,
  "source": "wasm_client"
}
```

Your Flutter app can consume this via a local socket bridge or backend relay.

## 4) Run local WS bridge (for Flutter/backend integration)

`ws_bridge.py` receives predictions from browser WASM and republishes them.

From repo root:

```powershell
cd test\light_weight\wasm
python .\ws_bridge.py
```

Endpoints:

- Ingest from browser: `ws://127.0.0.1:8787/ws/sign`
- Subscribe stream: `ws://127.0.0.1:8787/ws/stream`
- Latest prediction over HTTP: `http://127.0.0.1:8787/latest`
- Health: `http://127.0.0.1:8787/health`

Recommended flow:

1. Start `ws_bridge.py`
2. Start static server (`python -m http.server 8080` from `test`)
3. Open `http://127.0.0.1:8080/light_weight/wasm/web/`
4. In page, set WS URL to `ws://127.0.0.1:8787/ws/sign` and connect
5. Flutter can read `GET /latest` or subscribe to `ws://127.0.0.1:8787/ws/stream`

## Notes

- This uses your **lightweight landmarks model** (`model.tflite`), not YOLO `best.pt`.
- For mobile Flutter app runtime, native TFLite is usually faster than WASM.
- WASM path is great for web/WebView, quick iteration, and cross-platform demos.
