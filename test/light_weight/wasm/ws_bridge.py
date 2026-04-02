from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

try:
    import tensorflow as tf
except Exception:  # pragma: no cover
    tf = None

try:
    import cv2
except Exception:  # pragma: no cover
    cv2 = None

try:
    import mediapipe as mp
except Exception:  # pragma: no cover
    mp = None


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


def _landmarks_to_feature_vector(result: Any) -> list[float] | None:
    hand_landmarks = getattr(result, "multi_hand_landmarks", None)
    if not hand_landmarks:
        return None

    handedness = getattr(result, "multi_handedness", None) or []

    left = np.zeros(63, dtype=np.float32)
    right = np.zeros(63, dtype=np.float32)

    for i, hand in enumerate(hand_landmarks):
        if hand is None or len(getattr(hand, "landmark", [])) != 21:
            continue

        label = "Right"
        if i < len(handedness) and handedness[i].classification:
            label = handedness[i].classification[0].label or "Right"

        wrist = hand.landmark[0]
        coords = np.zeros(63, dtype=np.float32)
        for j, point in enumerate(hand.landmark):
            base = j * 3
            coords[base] = float(point.x - wrist.x)
            coords[base + 1] = float(point.y - wrist.y)
            coords[base + 2] = float(point.z - wrist.z)

        if label == "Left":
            left = coords
        else:
            right = coords

    has_left = bool(np.any(left))
    has_right = bool(np.any(right))
    if not has_left and not has_right:
        return None

    # Keep parity with browser path: if only one hand is present, map it to "left" slot.
    if not has_left and has_right:
        left = right
        right = np.zeros(63, dtype=np.float32)

    out = np.concatenate([left, right], axis=0)
    return out.tolist()


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


@app.post("/predict_video")
async def predict_video(
    file: UploadFile = File(...),
    frame_stride: int = 2,
    min_confidence: float = 0.0,
    only_predictions: bool = True,
    max_frames: int = 0,
) -> dict[str, Any]:
    if not file.content_type or not file.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Upload a video file.")
    if frame_stride < 1 or frame_stride > 60:
        raise HTTPException(status_code=400, detail="frame_stride must be between 1 and 60.")
    if min_confidence < 0.0 or min_confidence > 1.0:
        raise HTTPException(status_code=400, detail="min_confidence must be between 0 and 1.")
    if max_frames < 0 or max_frames > 20000:
        raise HTTPException(status_code=400, detail="max_frames must be between 0 and 20000.")

    if not hub.server_infer_enabled:
        raise HTTPException(
            status_code=503,
            detail=f"Server inference unavailable: {hub.infer_error or 'unknown error'}",
        )
    if cv2 is None:
        raise HTTPException(status_code=503, detail="OpenCV (cv2) is not installed.")
    if mp is None:
        raise HTTPException(status_code=503, detail="MediaPipe is not installed.")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="The uploaded video file is empty.")

    temp_path = BASE_DIR / f"__tmp_upload_{int(time.time() * 1000)}.mp4"
    capture = None
    try:
        temp_path.write_bytes(data)
        capture = cv2.VideoCapture(str(temp_path))
        if not capture.isOpened():
            raise HTTPException(status_code=400, detail="Could not open the uploaded video.")

        fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

        detector = mp.solutions.hands.Hands(
            static_image_mode=False,
            model_complexity=0,
            max_num_hands=2,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

        frames: list[dict[str, Any]] = []
        frame_index = -1
        processed = 0
        predicted = 0
        started = time.perf_counter()

        try:
            while True:
                ok, frame = capture.read()
                if not ok:
                    break
                frame_index += 1

                if frame_index % frame_stride != 0:
                    continue
                if max_frames > 0 and processed >= max_frames:
                    break

                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = detector.process(rgb)
                features = _landmarks_to_feature_vector(result)
                timestamp_ms = (
                    (1000.0 * frame_index / fps) if fps > 0 else (processed * 1000.0 / 30.0)
                )

                payload: dict[str, Any] = {
                    "frame_index": frame_index,
                    "timestamp_ms": round(timestamp_ms, 2),
                    "hands": len(getattr(result, "multi_hand_landmarks", []) or []),
                }

                evt = _predict_from_features(features) if features is not None else None
                if evt is not None and evt.confidence >= min_confidence:
                    payload.update(
                        {
                            "label": evt.label,
                            "confidence": round(float(evt.confidence), 6),
                            "class_index": evt.class_index,
                        }
                    )
                    predicted += 1

                if (not only_predictions) or ("label" in payload):
                    frames.append(payload)

                processed += 1
        finally:
            detector.close()

        elapsed_ms = (time.perf_counter() - started) * 1000.0
        best_label = ""
        if frames:
            counts: dict[str, int] = {}
            for row in frames:
                label = row.get("label")
                if not label:
                    continue
                counts[label] = counts.get(label, 0) + 1
            if counts:
                best_label = max(counts.items(), key=lambda kv: kv[1])[0]

        return {
            "filename": file.filename,
            "video_meta": {
                "fps": round(fps, 3),
                "frame_count": frame_count,
                "width": width,
                "height": height,
            },
            "params": {
                "frame_stride": frame_stride,
                "min_confidence": min_confidence,
                "only_predictions": only_predictions,
                "max_frames": max_frames,
            },
            "summary": {
                "processed_frames": processed,
                "returned_frames": len(frames),
                "predicted_frames": predicted,
                "top_label": best_label,
                "elapsed_ms": round(elapsed_ms, 2),
            },
            "frames": frames,
        }
    finally:
        if capture is not None:
            capture.release()
        try:
            temp_path.unlink(missing_ok=True)
        except Exception:
            pass


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
