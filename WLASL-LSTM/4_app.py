"""
STEP 4 — Real-time sign language detection using trained LSTM model.

Usage:
    python 4_app.py \
        --model models/sign_model.h5 \
        --labels models/labels.json \
        --sequence_length 30 \
        --threshold 0.6 \
        --stability 8

Controls:
    Q — quit
"""

import os
import json
import argparse
import collections
import time
import urllib.request
import cv2
import numpy as np
import mediapipe as mp
import tensorflow as tf

# ── MediaPipe new API (0.10+) ─────────────────────────────────────────────────
BaseOptions        = mp.tasks.BaseOptions
HandLandmarker     = mp.tasks.vision.HandLandmarker
HandLandmarkerOpts = mp.tasks.vision.HandLandmarkerOptions
RunningMode        = mp.tasks.vision.RunningMode
drawing_utils      = mp.tasks.vision.drawing_utils
HandLandmarksConn  = mp.tasks.vision.HandLandmarksConnections

MODEL_PATH = os.path.join(os.path.dirname(__file__), "hand_landmarker.task")
MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"


def ensure_model():
    if not os.path.exists(MODEL_PATH):
        print("Downloading MediaPipe hand landmarker model...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print(f"Saved -> {MODEL_PATH}")


def make_detector() -> HandLandmarker:
    ensure_model()
    opts = HandLandmarkerOpts(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=RunningMode.IMAGE,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return HandLandmarker.create_from_options(opts)


# ── Landmark helpers ──────────────────────────────────────────────────────────

def get_hand_landmarks(frame: np.ndarray, detector: HandLandmarker):
    """
    Returns (landmarks_63, hand_landmarks_obj | None).
    landmarks_63 is zeros if no hand detected.
    """
    rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result   = detector.detect(mp_image)

    if result.hand_landmarks:
        lm  = result.hand_landmarks[0]
        raw = np.array([[p.x, p.y, p.z] for p in lm], dtype=np.float32).flatten()
        return raw, result.hand_landmarks[0]

    return np.zeros(63, dtype=np.float32), None


def normalize_landmarks(landmarks: np.ndarray) -> np.ndarray:
    pts  = landmarks.reshape(21, 3)
    pts -= pts[0].copy()
    scale = np.linalg.norm(pts[9])
    if scale > 1e-6:
        pts /= scale
    return pts.flatten()


# ── Word buffer with stability gate + 600 ms dedupe ──────────────────────────

class WordBuffer:
    def __init__(self, stability: int = 8, dedupe_ms: int = 600):
        self.stability    = stability
        self.dedupe_ms    = dedupe_ms
        self.recent_preds = collections.deque(maxlen=stability)
        self.sentence: list = []
        self._last_word   = ""
        self._last_time   = 0.0

    def push(self, label: str):
        self.recent_preds.append(label)
        if len(self.recent_preds) < self.stability:
            return None
        if len(set(self.recent_preds)) != 1:
            return None
        now = time.time()
        if label == self._last_word and (now - self._last_time) * 1000 < self.dedupe_ms:
            return None
        self._last_word = label
        self._last_time = now
        self.sentence.append(label)
        if len(self.sentence) > 10:
            self.sentence = self.sentence[-10:]
        return label


# ── Inference engine ──────────────────────────────────────────────────────────

class SignDetector:
    def __init__(self, model_path: str, labels: list, sequence_length: int, threshold: float):
        self.labels          = labels
        self.sequence_length = sequence_length
        self.threshold       = threshold
        self.sequence        = collections.deque(maxlen=sequence_length)

        if model_path.endswith(".tflite"):
            self._interpreter = tf.lite.Interpreter(model_path=model_path)
            self._interpreter.allocate_tensors()
            self._input_idx   = self._interpreter.get_input_details()[0]["index"]
            self._output_idx  = self._interpreter.get_output_details()[0]["index"]
            self._use_tflite  = True
        else:
            self._model      = tf.keras.models.load_model(model_path)
            self._use_tflite = False

    def predict(self, landmarks: np.ndarray):
        self.sequence.append(landmarks)
        if len(self.sequence) < self.sequence_length:
            return None, 0.0

        seq_array = np.array(self.sequence, dtype=np.float32)[np.newaxis]

        if self._use_tflite:
            self._interpreter.set_tensor(self._input_idx, seq_array)
            self._interpreter.invoke()
            probs = self._interpreter.get_tensor(self._output_idx)[0]
        else:
            probs = self._model.predict(seq_array, verbose=0)[0]

        idx        = int(np.argmax(probs))
        confidence = float(probs[idx])

        if confidence < self.threshold:
            return None, confidence

        return self.labels[idx], confidence

    def get_probs(self) -> np.ndarray:
        """Get latest probability array for visualization."""
        if len(self.sequence) < self.sequence_length:
            return np.zeros(len(self.labels))
        seq_array = np.array(self.sequence, dtype=np.float32)[np.newaxis]
        if self._use_tflite:
            self._interpreter.set_tensor(self._input_idx, seq_array)
            self._interpreter.invoke()
            return self._interpreter.get_tensor(self._output_idx)[0]
        return self._model.predict(seq_array, verbose=0)[0]


# ── Drawing helpers ───────────────────────────────────────────────────────────

def draw_hand(frame: np.ndarray, hand_landmarks_obj, image_width: int, image_height: int):
    """Draw hand skeleton using new MediaPipe API."""
    if hand_landmarks_obj is None:
        return

    # Convert normalized landmarks to pixel coords for drawing
    landmark_list = mp.tasks.vision.HandLandmarker
    connections = [
        (0,1),(1,2),(2,3),(3,4),           # thumb
        (0,5),(5,6),(6,7),(7,8),           # index
        (0,9),(9,10),(10,11),(11,12),       # middle
        (0,13),(13,14),(14,15),(15,16),     # ring
        (0,17),(17,18),(18,19),(19,20),     # pinky
        (5,9),(9,13),(13,17),              # palm
    ]

    pts = []
    for lm in hand_landmarks_obj:
        pts.append((int(lm.x * image_width), int(lm.y * image_height)))

    for (a, b) in connections:
        cv2.line(frame, pts[a], pts[b], (245, 66, 230), 2)
    for i, pt in enumerate(pts):
        r = 4 if i in (4, 8, 12, 16, 20) else 3
        cv2.circle(frame, pt, r, (121, 44, 250), -1)


def draw_prob_bars(frame: np.ndarray, probs: np.ndarray, labels: list, top_k: int = 5):
    h, _ = frame.shape[:2]
    order  = np.argsort(probs)[::-1][:top_k]
    bar_h  = 20
    spacing = 26
    y0     = h - top_k * spacing - 10

    for rank, idx in enumerate(order):
        p     = float(probs[idx])
        label = labels[idx]
        y     = y0 + rank * spacing
        cv2.rectangle(frame, (10, y), (10 + int(p * 200), y + bar_h), (33, 150, 243), -1)
        cv2.putText(frame, f"{label}: {p:.2f}", (15, y + 15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)


def draw_sentence(frame: np.ndarray, sentence: list):
    h, w = frame.shape[:2]
    cv2.rectangle(frame, (0, 0), (w, 45), (245, 117, 16), -1)
    text = " ".join(sentence) if sentence else "..."
    cv2.putText(frame, text, (10, 32), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)


def draw_fps(frame: np.ndarray, fps: float):
    cv2.putText(frame, f"FPS: {fps:.1f}", (10, 70),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)


# ── Main loop ─────────────────────────────────────────────────────────────────

def run(args):
    with open(args.labels) as f:
        labels = json.load(f)

    detector    = SignDetector(args.model, labels, args.sequence_length, args.threshold)
    word_buffer = WordBuffer(stability=args.stability)

    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)

    prev_time    = time.time()
    probs_display = np.zeros(len(labels), dtype=np.float32)

    with make_detector() as mp_detector:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            frame = cv2.flip(frame, 1)
            h, w  = frame.shape[:2]

            raw_lm, hand_lm_obj = get_hand_landmarks(frame, mp_detector)
            norm_lm = normalize_landmarks(raw_lm)

            draw_hand(frame, hand_lm_obj, w, h)

            label, confidence = detector.predict(norm_lm)

            if label is not None:
                probs_display = detector.get_probs()
                confirmed = word_buffer.push(label)
                if confirmed:
                    print(f"Confirmed: {confirmed}  ({confidence:.2f})")

            draw_sentence(frame, word_buffer.sentence)
            draw_fps(frame, 1.0 / max(time.time() - prev_time, 1e-6))
            draw_prob_bars(frame, probs_display, labels)

            if label is not None:
                cv2.putText(frame, f"{label} ({confidence:.0%})", (10, 110),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 128), 2)

            prev_time = time.time()
            cv2.imshow("Sign Language Detection  |  Q to quit", frame)

            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    cap.release()
    cv2.destroyAllWindows()


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Real-time sign language detection")
    parser.add_argument("--model",           default="models/sign_model.h5",  help=".h5 or .tflite model")
    parser.add_argument("--labels",          default="models/labels.json",    help="labels.json path")
    parser.add_argument("--sequence_length", type=int,   default=30,          help="Frames per sequence")
    parser.add_argument("--threshold",       type=float, default=0.6,         help="Confidence threshold (0-1)")
    parser.add_argument("--stability",       type=int,   default=8,           help="Frames for confirmation")
    parser.add_argument("--camera",          type=int,   default=0,           help="Camera device index")
    parser.add_argument("--width",           type=int,   default=1280)
    parser.add_argument("--height",          type=int,   default=720)
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
