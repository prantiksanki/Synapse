# best.pt hosting

This folder now includes a small FastAPI server that hosts `best.pt` over HTTP.

## 1. Create a local environment

Use Python 3.12 for the best compatibility with `ultralytics`.

```bash
cd /Users/aasthikupadhyay/Desktop/Synapse/test
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## 2. Start the server

```bash
cd /Users/aasthikupadhyay/Desktop/Synapse/test
source .venv/bin/activate
uvicorn serve_best:app --host 0.0.0.0 --port 8000 --reload
```

The model is loaded from `test/best.pt` automatically on startup.

Optional environment variables:

```bash
MODEL_PATH=/absolute/path/to/best.pt
DEFAULT_CONFIDENCE=0.25
DEFAULT_IMGSZ=640
HOST=0.0.0.0
PORT=8000
```

## 3. Test it

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Prediction:

```bash
curl -X POST "http://127.0.0.1:8000/predict?conf=0.3" \
  -F "file=@/absolute/path/to/image.jpg"
```

The response returns the detected labels, confidences, and bounding boxes.
