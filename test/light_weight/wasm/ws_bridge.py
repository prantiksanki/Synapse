from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

try:
    import tensorflow as tf
except Exception:  # pragma: no cover
    tf = None


HOST = os.environ.get("WS_BRIDGE_HOST", "0.0.0.0")
PORT = int(os.environ.get("WS_BRIDGE_PORT", "8787"))
BASE_DIR = Path(__file__).resolve().parent
LW_DIR = BASE_DIR.parent
MODEL_PATH = Path(os.environ.get("WS_BRIDGE_MODEL", LW_DIR / "model.tflite")).resolve()
LABELS_PATH = Path(os.environ.get("WS_BRIDGE_LABELS", LW_DIR / "labels.txt")).resolve()
NORM_PATH = Path(
    os.environ.get("WS_BRIDGE_NORM", LW_DIR / "normalization.json")
).resolve()
LANDMARK_DIM = 126


@dataclass
class PredictionEvent:
    label: str
    confidence: float
    class_index: int
    timestamp_ms: int
    hands: int = 0
    source: str = "wasm_client"
    received_at_ms: int = 0


class ConnectionHub:
    def __init__(self) -> None:
        self._inputs: set[WebSocket] = set()
        self._watchers: set[WebSocket] = set()
        self.latest: PredictionEvent | None = None
        self.total_events = 0
        self.server_infer_enabled = False
        self.labels: list[str] = []
        self.mean: np.ndarray | None = None
        self.std: np.ndarray | None = None
        self.interpreter = None
        self.input_info = None
        self.output_info = None
        self.infer_error: str | None = None

    async def add_input(self, ws: WebSocket) -> None:
        await ws.accept()
        self._inputs.add(ws)

    async def add_watcher(self, ws: WebSocket) -> None:
        await ws.accept()
        self._watchers.add(ws)

    def remove_input(self, ws: WebSocket) -> None:
        self._inputs.discard(ws)

    def remove_watcher(self, ws: WebSocket) -> None:
        self._watchers.discard(ws)

    async def broadcast(self, payload: dict[str, Any]) -> None:
        dead: list[WebSocket] = []
        for ws in self._watchers:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self._watchers.discard(ws)


hub = ConnectionHub()
app = FastAPI(title="Synapse WASM WS Bridge", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def parse_prediction(payload: dict[str, Any]) -> PredictionEvent:
    label = str(payload.get("label", ""))
    confidence = float(payload.get("confidence", 0.0))
    class_index = int(payload.get("class_index", -1))
    timestamp_ms = int(payload.get("timestamp_ms", int(time.time() * 1000)))
    hands = int(payload.get("hands", 0))
    source = str(payload.get("source", "wasm_client"))
    return PredictionEvent(
        label=label,
        confidence=confidence,
        class_index=class_index,
        timestamp_ms=timestamp_ms,
        hands=hands,
        source=source,
        received_at_ms=int(time.time() * 1000),
    )


def _load_server_model() -> None:
    if tf is None:
        hub.infer_error = "TensorFlow is not installed in this Python environment."
        return
    if not (MODEL_PATH.exists() and LABELS_PATH.exists() and NORM_PATH.exists()):
        hub.infer_error = "Model/labels/normalization files are missing."
        return

    labels = [
        line.strip()
        for line in LABELS_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    norm = json.loads(NORM_PATH.read_text(encoding="utf-8"))
    mean = np.asarray(norm.get("mean", []), dtype=np.float32)
    std = np.asarray(norm.get("std", []), dtype=np.float32)
    if mean.shape[0] != LANDMARK_DIM or std.shape[0] != LANDMARK_DIM:
        hub.infer_error = "normalization.json shape mismatch."
        return

    interpreter = tf.lite.Interpreter(model_path=str(MODEL_PATH))
    interpreter.allocate_tensors()
    input_info = interpreter.get_input_details()[0]
    output_info = interpreter.get_output_details()[0]
    if int(input_info["shape"][-1]) != LANDMARK_DIM:
        hub.infer_error = "TFLite input dimension mismatch."
        return
    if int(output_info["shape"][-1]) != len(labels):
        hub.infer_error = "TFLite output classes do not match labels.txt."
        return

    hub.labels = labels
    hub.mean = mean
    hub.std = np.maximum(std, 1e-6)
    hub.interpreter = interpreter
    hub.input_info = input_info
    hub.output_info = output_info
    hub.server_infer_enabled = True
    hub.infer_error = None


def _predict_from_features(features: list[float]) -> PredictionEvent | None:
    if not hub.server_infer_enabled:
        return None
    if len(features) != LANDMARK_DIM:
        return None

    x = np.asarray(features, dtype=np.float32)
    x = (x - hub.mean) / hub.std

    input_info = hub.input_info
    output_info = hub.output_info
    interpreter = hub.interpreter

    input_dtype = input_info["dtype"]
    input_scale, input_zero_point = input_info.get("quantization", (0.0, 0))
    is_int8_input = input_dtype == np.int8 and input_scale != 0.0

    if is_int8_input:
        tensor = np.round(x / input_scale + input_zero_point).clip(-128, 127).astype(
            np.int8
        )
    else:
        tensor = x.astype(input_dtype, copy=False)

    tensor = np.expand_dims(tensor, axis=0)
    interpreter.set_tensor(input_info["index"], tensor)
    interpreter.invoke()
    raw = interpreter.get_tensor(output_info["index"])[0]

    output_scale, output_zero_point = output_info.get("quantization", (0.0, 0))
    is_int8_output = output_info["dtype"] == np.int8 and output_scale != 0.0
    probs = (
        (raw.astype(np.float32) - output_zero_point) * output_scale
        if is_int8_output
        else raw.astype(np.float32)
    )

    idx = int(np.argmax(probs))
    conf = float(probs[idx])
    label = hub.labels[idx] if 0 <= idx < len(hub.labels) else str(idx)
    return PredictionEvent(
        label=label,
        confidence=conf,
        class_index=idx,
        timestamp_ms=int(time.time() * 1000),
        hands=1,
        source="ws_bridge_tflite",
        received_at_ms=int(time.time() * 1000),
    )


@app.on_event("startup")
def _startup() -> None:
    _load_server_model()


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "message": "WASM WS bridge is running",
        "server_infer_enabled": hub.server_infer_enabled,
        "endpoints": {
            "ingest_ws": "/ws/sign",
            "subscribe_ws": "/ws/stream",
            "latest_http": "/latest",
            "health": "/health",
        },
    }


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "server_infer_enabled": hub.server_infer_enabled,
        "infer_error": hub.infer_error,
        "input_clients": len(hub._inputs),
        "stream_clients": len(hub._watchers),
        "total_events": hub.total_events,
        "has_latest": hub.latest is not None,
    }


@app.get("/latest")
def latest() -> dict[str, Any]:
    if hub.latest is None:
        return {"event": None}
    return {"event": asdict(hub.latest)}


@app.websocket("/ws/sign")
async def ingest_sign_predictions(websocket: WebSocket) -> None:
    await hub.add_input(websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"event": "error", "message": "Invalid JSON payload."})
                continue

            evt: PredictionEvent | None = None
            if payload.get("event") == "prediction":
                evt = parse_prediction(payload)
            elif payload.get("event") == "features":
                evt = _predict_from_features(payload.get("features", []))
                if evt is None:
                    await websocket.send_json(
                        {
                            "event": "error",
                            "message": "Invalid features payload or server inference unavailable.",
                        }
                    )
                    continue
            else:
                continue

            hub.latest = evt
            hub.total_events += 1

            print(
                f"[WASM] {evt.label:>2}  conf={evt.confidence:.3f}  "
                f"class={evt.class_index:>2}  hands={evt.hands}  ts={evt.timestamp_ms}",
                flush=True,
            )

            await hub.broadcast({"event": "prediction", "data": asdict(evt)})
            await websocket.send_json({"event": "prediction", "data": asdict(evt)})
    except WebSocketDisconnect:
        hub.remove_input(websocket)
    except Exception:
        hub.remove_input(websocket)


@app.websocket("/ws/stream")
async def stream_predictions(websocket: WebSocket) -> None:
    await hub.add_watcher(websocket)
    try:
        if hub.latest is not None:
            await websocket.send_json({"event": "prediction", "data": asdict(hub.latest)})
        while True:
            # Keep connection open; client can optionally send pings.
            await websocket.receive_text()
    except WebSocketDisconnect:
        hub.remove_watcher(websocket)
    except Exception:
        hub.remove_watcher(websocket)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("ws_bridge:app", host=HOST, port=PORT, reload=False)
