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
import cv2
import numpy as np
import mediapipe as mp
import tensorflow as tf



# ── Landmark helpers (mirrors 1_extract_landmarks.py) ────────────────────────

mp_hands_module = mp.solutions.hands
mp_drawing       = mp.solutions.drawing_utils


def get_hand_landmarks(frame: np.ndarray, hands_model) -> np.ndarray:
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    rgb.flags.writeable = False
    results = hands_model.process(rgb)

    if results.multi_hand_landmarks:
        lm = results.multi_hand_landmarks[0].landmark
        raw = np.array([[p.x, p.y, p.z] for p in lm], dtype=np.float32).flatten()
        return raw, results.multi_hand_landmarks[0]

    return np.zeros(63, dtype=np.float32), None


def normalize_landmarks(landmarks: np.ndarray) -> np.ndarray:
    pts = landmarks.reshape(21, 3)
    pts -= pts[0].copy()
    scale = np.linalg.norm(pts[9])
    if scale > 1e-6:
        pts /= scale
    return pts.flatten()


# ── Word buffer with stability gate + 600 ms dedupe ─────────────────────────

class WordBuffer:
    def __init__(self, stability: int = 8, dedupe_ms: int = 600):
        self.stability   = stability          # frames with same prediction
        self.dedupe_ms   = dedupe_ms          # ignore repeat within N ms
        self.recent_preds: collections.deque = collections.deque(maxlen=stability)
        self.sentence: list[str]             = []
        self._last_word: str                 = ""
        self._last_time: float               = 0.0

    def push(self, label: str) -> str | None:
        """Push a prediction. Returns confirmed word or None."""
        self.recent_preds.append(label)

        if len(self.recent_preds) < self.stability:
            return None

        # All recent predictions must agree
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


# ── Inference engine ─────────────────────────────────────────────────────────

class SignDetector:
    def __init__(self, model_path: str, labels: list[str], sequence_length: int, threshold: float):
        self.labels          = labels
        self.sequence_length = sequence_length
        self.threshold       = threshold
        self.sequence: collections.deque = collections.deque(maxlen=sequence_length)

        # Load model — supports .h5 and .tflite
        if model_path.endswith(".tflite"):
            self._interpreter = tf.lite.Interpreter(model_path=model_path)
            self._interpreter.allocate_tensors()
            self._input_idx  = self._interpreter.get_input_details()[0]["index"]
            self._output_idx = self._interpreter.get_output_details()[0]["index"]
            self._use_tflite = True
        else:
            self._model      = tf.keras.models.load_model(model_path)
            self._use_tflite = False

    def predict(self, landmarks: np.ndarray) -> tuple[str, float] | tuple[None, float]:
        """
        Feed one frame of normalized landmarks (63,).
        Returns (label, confidence) when sequence is full, else (None, 0).
        """
        self.sequence.append(landmarks)

        if len(self.sequence) < self.sequence_length:
            return None, 0.0

        seq_array = np.array(self.sequence, dtype=np.float32)[np.newaxis]  # (1,30,63)

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


# ── Drawing helpers ──────────────────────────────────────────────────────────

def draw_prob_bars(frame, probs, labels, top_k=5):
    """Draw top-K probability bars at the bottom-left."""
    h, w = frame.shape[:2]
    order = np.argsort(probs)[::-1][:top_k]
    bar_h, spacing = 20, 26
    y0 = h - top_k * spacing - 10

    for rank, idx in enumerate(order):
        p     = probs[idx]
        label = labels[idx]
        y     = y0 + rank * spacing
        bar_w = int(p * 200)

        cv2.rectangle(frame, (10, y), (10 + bar_w, y + bar_h), (33, 150, 243), -1)
        cv2.putText(frame, f"{label}: {p:.2f}", (15, y + 15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)


def draw_sentence(frame, sentence: list[str]):
    h, w = frame.shape[:2]
    cv2.rectangle(frame, (0, 0), (w, 45), (245, 117, 16), -1)
    text = " ".join(sentence) if sentence else "..."
    cv2.putText(frame, text, (10, 32), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)


def draw_fps(frame, fps: float):
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

    prev_time = time.time()
    probs_display = np.zeros(len(labels), dtype=np.float32)

    with mp_hands_module.Hands(
        static_image_mode=False,
        max_num_hands=1,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as hands:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            frame = cv2.flip(frame, 1)  # mirror

            # Landmark extraction
            raw_lm, hand_lm_obj = get_hand_landmarks(frame, hands)
            norm_lm = normalize_landmarks(raw_lm)

            # Draw hand skeleton if detected
            if hand_lm_obj is not None:
                mp_drawing.draw_landmarks(
                    frame, hand_lm_obj,
                    mp_hands_module.HAND_CONNECTIONS,
                    mp_drawing.DrawingSpec(color=(121, 44, 250), thickness=2, circle_radius=2),
                    mp_drawing.DrawingSpec(color=(245, 66, 230), thickness=2),
                )

            # Inference
            label, confidence = detector.predict(norm_lm)

            if label is not None:
                # Update display probs (only when we have a full prediction)
                if not detector._use_tflite:
                    seq_arr = np.array(detector.sequence, dtype=np.float32)[np.newaxis]
                    probs_display = detector._model.predict(seq_arr, verbose=0)[0]

                confirmed = word_buffer.push(label)
                if confirmed:
                    print(f"Confirmed: {confirmed}  ({confidence:.2f})")

            # UI
            draw_sentence(frame, word_buffer.sentence)
            draw_fps(frame, 1.0 / max(time.time() - prev_time, 1e-6))
            draw_prob_bars(frame, probs_display, labels)

            # Current prediction overlay
            if label is not None:
                cv2.putText(frame, f"{label} ({confidence:.0%})", (10, 110),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 128), 2)

            prev_time = time.time()
            cv2.imshow("Sign Language Detection — Q to quit", frame)

            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    cap.release()
    cv2.destroyAllWindows()


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Real-time sign language detection")
    parser.add_argument("--model",           default="models/sign_model.h5",  help=".h5 or .tflite model path")
    parser.add_argument("--labels",          default="models/labels.json",    help="labels.json path")
    parser.add_argument("--sequence_length", type=int,   default=30,          help="Frames per sequence")
    parser.add_argument("--threshold",       type=float, default=0.6,         help="Confidence threshold (0–1)")
    parser.add_argument("--stability",       type=int,   default=8,           help="Frames required for confirmation")
    parser.add_argument("--camera",          type=int,   default=0,           help="Camera device index")
    parser.add_argument("--width",           type=int,   default=1280)
    parser.add_argument("--height",          type=int,   default=720)
    args = parser.parse_args()

    run(args)


if __name__ == "__main__":
    main()
