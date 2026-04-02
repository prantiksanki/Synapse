from __future__ import annotations

import os
import tempfile
import time
from contextlib import asynccontextmanager
from io import BytesIO
from pathlib import Path
from threading import Lock
from typing import Any

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect
from PIL import Image, UnidentifiedImageError
from ultralytics import YOLO


BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = Path(os.environ.get("MODEL_PATH", BASE_DIR / "best.pt")).resolve()
DEFAULT_CONFIDENCE = float(os.environ.get("DEFAULT_CONFIDENCE", "0.25"))
DEFAULT_IMGSZ = int(os.environ.get("DEFAULT_IMGSZ", "640"))
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8000"))


@asynccontextmanager
async def lifespan(_: FastAPI):
    get_model()
    yield


app = FastAPI(
    title="Synapse best.pt Inference Server",
    version="1.0.0",
    description="Hosts the YOLO best.pt model from the test folder and exposes an HTTP prediction API.",
    lifespan=lifespan,
)

_model: YOLO | None = None
_model_lock = Lock()


def get_model() -> YOLO:
    global _model

    if _model is not None:
        return _model

    with _model_lock:
        if _model is None:
            if not MODEL_PATH.exists():
                raise RuntimeError(f"Model file not found: {MODEL_PATH}")
            _model = YOLO(str(MODEL_PATH))
    return _model


def get_label(names: Any, class_index: int) -> str:
    if isinstance(names, dict):
        return str(names.get(class_index, class_index))
    if isinstance(names, list) and 0 <= class_index < len(names):
        return str(names[class_index])
    return str(class_index)


def serialize_result(result: Any) -> dict[str, Any]:
    boxes = result.boxes
    detections: list[dict[str, Any]] = []

    if boxes is not None and len(boxes) > 0:
        xyxy_values = boxes.xyxy.cpu().tolist()
        confidences = boxes.conf.cpu().tolist()
        class_ids = boxes.cls.cpu().tolist()

        for xyxy, confidence, class_id in zip(xyxy_values, confidences, class_ids):
            class_index = int(class_id)
            detections.append(
                {
                    "class_id": class_index,
                    "label": get_label(result.names, class_index),
                    "confidence": round(float(confidence), 6),
                    "bbox_xyxy": [round(float(value), 3) for value in xyxy],
                }
            )

    return {
        "image_shape": list(result.orig_shape),
        "count": len(detections),
        "detections": detections,
    }


def serialize_frame_result(
    result: Any,
    *,
    frame_index: int,
    timestamp_ms: float,
) -> dict[str, Any]:
    serialized = serialize_result(result)
    return {
        "frame_index": frame_index,
        "timestamp_ms": round(float(timestamp_ms), 2),
        "count": serialized["count"],
        "detections": serialized["detections"],
        "image_shape": serialized["image_shape"],
    }


@app.get("/")
def root() -> dict[str, Any]:
    model = get_model()
    return {
        "message": "best.pt model server is running",
        "model_path": str(MODEL_PATH),
        "class_count": len(model.names),
        "endpoints": {
            "health": "/health",
            "predict_image": "/predict",
            "predict_video": "/predict_video",
            "predict_realtime_ws": "/ws/predict_realtime",
        },
    }


@app.get("/health")
def health() -> dict[str, Any]:
    model = get_model()
    return {
        "status": "ok",
        "model_loaded": True,
        "model_path": str(MODEL_PATH),
        "class_count": len(model.names),
    }


@app.post("/predict")
async def predict(
    file: UploadFile = File(...),
    conf: float = Query(DEFAULT_CONFIDENCE, ge=0.0, le=1.0),
    imgsz: int = Query(DEFAULT_IMGSZ, ge=32, le=2048),
) -> dict[str, Any]:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Upload an image file.")

    try:
        image_bytes = await file.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="The uploaded file is empty.")
        image = Image.open(BytesIO(image_bytes)).convert("RGB")
    except UnidentifiedImageError as exc:
        raise HTTPException(status_code=400, detail="Could not decode the uploaded image.") from exc

    model = get_model()
    results = model.predict(source=image, conf=conf, imgsz=imgsz, verbose=False)

    if not results:
        return {
            "filename": file.filename,
            "count": 0,
            "detections": [],
        }

    serialized = serialize_result(results[0])
    return {
        "filename": file.filename,
        "count": serialized["count"],
        "detections": serialized["detections"],
        "image_shape": serialized["image_shape"],
    }


@app.post("/predict_video")
async def predict_video(
    file: UploadFile = File(...),
    conf: float = Query(DEFAULT_CONFIDENCE, ge=0.0, le=1.0),
    imgsz: int = Query(DEFAULT_IMGSZ, ge=32, le=2048),
    frame_stride: int = Query(1, ge=1, le=60),
    only_detections: bool = Query(False),
    max_frames: int = Query(0, ge=0, le=20000),
) -> dict[str, Any]:
    """
    Batch video inference (frame-by-frame).
    Upload a video and receive detections for each sampled frame.
    """
    if not file.content_type or not file.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Upload a video file.")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="The uploaded video file is empty.")

    suffix = Path(file.filename or "upload.mp4").suffix or ".mp4"
    temp_path: Path | None = None
    capture = None
    model = get_model()

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(data)
            temp_path = Path(tmp.name)

        capture = cv2.VideoCapture(str(temp_path))
        if not capture.isOpened():
            raise HTTPException(status_code=400, detail="Could not open the uploaded video.")

        fps = capture.get(cv2.CAP_PROP_FPS) or 0.0
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

        frames: list[dict[str, Any]] = []
        frame_index = -1
        processed = 0
        started = time.perf_counter()

        while True:
            ok, frame = capture.read()
            if not ok:
                break
            frame_index += 1

            if frame_index % frame_stride != 0:
                continue
            if max_frames > 0 and processed >= max_frames:
                break

            results = model.predict(source=frame, conf=conf, imgsz=imgsz, verbose=False)
            if not results:
                continue

            timestamp_ms = (1000.0 * frame_index / fps) if fps > 0 else (processed * 1000.0 / 30.0)
            frame_payload = serialize_frame_result(
                results[0],
                frame_index=frame_index,
                timestamp_ms=timestamp_ms,
            )
            if (not only_detections) or frame_payload["count"] > 0:
                frames.append(frame_payload)
            processed += 1

        elapsed_ms = (time.perf_counter() - started) * 1000.0
        total_detections = sum(f["count"] for f in frames)

        return {
            "filename": file.filename,
            "video_meta": {
                "fps": round(float(fps), 3),
                "frame_count": frame_count,
                "width": width,
                "height": height,
            },
            "params": {
                "conf": conf,
                "imgsz": imgsz,
                "frame_stride": frame_stride,
                "only_detections": only_detections,
                "max_frames": max_frames,
            },
            "summary": {
                "processed_frames": processed,
                "returned_frames": len(frames),
                "total_detections": total_detections,
                "elapsed_ms": round(elapsed_ms, 2),
            },
            "frames": frames,
        }
    finally:
        if capture is not None:
            capture.release()
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except Exception:
                pass


@app.websocket("/ws/predict_realtime")
async def predict_realtime(websocket: WebSocket):
    """
    Real-time inference socket.
    Client sends JPEG/PNG frame bytes; server responds with one JSON prediction per frame.
    """
    await websocket.accept()
    model = get_model()
    frame_index = 0

    try:
        while True:
            message = await websocket.receive()

            if message.get("type") == "websocket.disconnect":
                break

            frame_bytes = message.get("bytes")
            if not frame_bytes:
                # Ignore non-binary messages to keep the socket simple and robust.
                continue

            np_buf = np.frombuffer(frame_bytes, dtype=np.uint8)
            frame = cv2.imdecode(np_buf, cv2.IMREAD_COLOR)
            if frame is None:
                await websocket.send_json(
                    {
                        "event": "error",
                        "frame_index": frame_index,
                        "message": "Could not decode frame bytes as an image.",
                    }
                )
                continue

            results = model.predict(source=frame, conf=DEFAULT_CONFIDENCE, imgsz=DEFAULT_IMGSZ, verbose=False)
            if not results:
                await websocket.send_json(
                    {
                        "event": "prediction",
                        "frame_index": frame_index,
                        "timestamp_ms": round(time.time() * 1000.0, 2),
                        "count": 0,
                        "detections": [],
                    }
                )
                frame_index += 1
                continue

            payload = serialize_frame_result(
                results[0],
                frame_index=frame_index,
                timestamp_ms=time.time() * 1000.0,
            )
            payload["event"] = "prediction"
            await websocket.send_json(payload)
            frame_index += 1
    except WebSocketDisconnect:
        return
    except Exception as exc:
        try:
            await websocket.send_json({"event": "error", "message": str(exc)})
        except Exception:
            pass


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("serve_best:app", host=HOST, port=PORT, reload=False)
