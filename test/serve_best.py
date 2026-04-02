from __future__ import annotations

import os
from contextlib import asynccontextmanager
from io import BytesIO
from pathlib import Path
from threading import Lock
from typing import Any

from fastapi import FastAPI, File, HTTPException, Query, UploadFile
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


@app.get("/")
def root() -> dict[str, Any]:
    model = get_model()
    return {
        "message": "best.pt model server is running",
        "model_path": str(MODEL_PATH),
        "class_count": len(model.names),
        "endpoints": {
            "health": "/health",
            "predict": "/predict",
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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("serve_best:app", host=HOST, port=PORT, reload=False)
