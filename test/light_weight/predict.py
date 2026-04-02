import argparse
import json
import time
from collections import Counter, deque
from pathlib import Path
from typing import List, Tuple

import numpy as np

try:
    import cv2
except ImportError:
    cv2 = None

try:
    import mediapipe as mp
except ImportError:
    mp = None

try:
    import tensorflow as tf
except ImportError:
    tf = None

# 21 landmarks x (x, y, z) x 2 hands = 126 features
LANDMARK_DIM = 126


class DualHandLandmarkExtractor:
    """
    Extracts x,y,z for up to 2 hands per frame using MediaPipe Tasks API.
    Returns a 126-dim vector: left_hand (63) + right_hand (63).
    If only one hand is visible, the missing hand's features are zeroed out.
    Landmark 0 (wrist) is subtracted per hand for translation invariance,
    matching the wrist-relative normalisation applied during training.
    """

    # Candidates for the hand_landmarker.task model file.
    _TASK_CANDIDATES = [
        Path(__file__).resolve().parent / "hand_landmarker.task",
        Path(__file__).resolve().parent.parent / "hand_landmarker.task",
    ]

    def __init__(self, task_model: Path | None = None) -> None:
        if mp is None:
            raise RuntimeError("MediaPipe is not installed. Install with: pip install mediapipe")

        self._last_result = None  # stores latest result from live-stream callback

        if hasattr(mp, "solutions"):
            self._mode = "solutions"
            self._detector = mp.solutions.hands.Hands(
                static_image_mode=False,
                max_num_hands=2,
                model_complexity=0,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            )
        elif hasattr(mp, "tasks"):
            self._mode = "tasks"
            model_path = self._resolve_task_model(task_model)
            vision = mp.tasks.vision

            def _callback(result, output_image, timestamp_ms):
                self._last_result = result

            options = vision.HandLandmarkerOptions(
                base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
                running_mode=vision.RunningMode.LIVE_STREAM,
                num_hands=2,
                min_hand_detection_confidence=0.5,
                min_hand_presence_confidence=0.5,
                min_tracking_confidence=0.5,
                result_callback=_callback,
            )
            self._detector = vision.HandLandmarker.create_from_options(options)
            self._ts_ms = 0
        else:
            raise RuntimeError("Unsupported MediaPipe version: neither 'solutions' nor 'tasks' API found.")

    @classmethod
    def _resolve_task_model(cls, task_model: Path | None) -> Path:
        candidates = ([task_model] if task_model else []) + cls._TASK_CANDIDATES
        for p in candidates:
            if p and p.exists():
                return p.resolve()
        raise FileNotFoundError(
            "hand_landmarker.task not found. Checked:\n"
            + "\n".join(str(p) for p in candidates if p)
            + "\nDownload from MediaPipe docs and place it in test/light_weight/."
        )

    def extract(self, frame_bgr: np.ndarray) -> np.ndarray | None:
        """
        Returns a (126,) float32 array or None if no hands detected.
        Order: [left_hand x0,y0,z0 ... x20,y20,z20,
                right_hand x0,y0,z0 ... x20,y20,z20]
        """
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)

        if self._mode == "solutions":
            frame_rgb.flags.writeable = False
            result = self._detector.process(frame_rgb)
            hand_landmarks_list = result.multi_hand_landmarks or []
            handedness_list = result.multi_handedness or []
            hands = [
                (handedness.classification[0].label, lms.landmark)
                for lms, handedness in zip(hand_landmarks_list, handedness_list)
            ]
        else:
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
            self._ts_ms += 1
            self._detector.detect_async(mp_image, self._ts_ms)
            result = self._last_result
            if result is None or not result.hand_landmarks:
                return None
            hands = [
                (result.handedness[i][0].display_name, result.hand_landmarks[i])
                for i in range(len(result.hand_landmarks))
            ]

        if not hands:
            return None

        left_coords  = np.zeros((21, 3), dtype=np.float32)
        right_coords = np.zeros((21, 3), dtype=np.float32)

        for label, lms in hands:
            coords = np.array([[lm.x, lm.y, lm.z] for lm in lms], dtype=np.float32)
            coords -= coords[0]  # wrist-relative
            if label == "Left":
                left_coords = coords
            else:
                right_coords = coords

        # The training dataset uses the LEFT hand slot for all one-hand signs
        # (right hand is absent/zeroed). If MediaPipe only detects one hand and
        # it landed in the right slot (mirror flip), move it to left so the
        # features match what the model was trained on.
        left_present  = np.any(left_coords  != 0)
        right_present = np.any(right_coords != 0)
        if right_present and not left_present:
            left_coords  = right_coords
            right_coords = np.zeros((21, 3), dtype=np.float32)

        if not left_present and not right_present:
            return None

        return np.concatenate([left_coords.flatten(), right_coords.flatten()])

    def close(self) -> None:
        if self._detector is not None and hasattr(self._detector, "close"):
            self._detector.close()


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Real-time ISL sign-language inference with MediaPipe + TFLite."
    )
    parser.add_argument(
        "--model", type=Path, default=script_dir / "model.tflite", help="Path to TFLite model."
    )
    parser.add_argument(
        "--labels", type=Path, default=script_dir / "labels.txt", help="Path to labels.txt."
    )
    parser.add_argument(
        "--norm", type=Path, default=script_dir / "normalization.json", help="Path to normalization stats."
    )
    parser.add_argument("--camera-id", type=int, default=0, help="OpenCV camera index.")
    parser.add_argument(
        "--history", type=int, default=7, help="Prediction smoothing buffer length."
    )
    parser.add_argument(
        "--min-confidence", type=float, default=0.35, help="Min confidence before showing class name."
    )
    parser.add_argument(
        "--stable-seconds",
        type=float,
        default=2.0,
        help="Time a predicted symbol must stay stable before it is shown.",
    )
    parser.add_argument("--flip", action="store_true", help="Mirror webcam image for natural UX.")
    parser.add_argument(
        "--hand-model",
        type=Path,
        default=script_dir.parent / "hand_landmarker.task",
        help="Path to hand_landmarker.task (required for MediaPipe Tasks API).",
    )
    return parser.parse_args()


def load_labels(path: Path) -> List[str]:
    if not path.exists():
        raise FileNotFoundError(f"labels.txt not found: {path}")
    labels = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not labels:
        raise RuntimeError("labels.txt is empty.")
    return labels


def load_norm(path: Path) -> Tuple[np.ndarray, np.ndarray]:
    if not path.exists():
        raise FileNotFoundError(f"normalization file not found: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    mean = np.asarray(payload.get("mean", []), dtype=np.float32)
    std = np.asarray(payload.get("std", []), dtype=np.float32)
    if mean.shape[0] != LANDMARK_DIM or std.shape[0] != LANDMARK_DIM:
        raise RuntimeError(
            f"normalization.json must contain mean/std arrays of length {LANDMARK_DIM}."
        )
    return mean, np.maximum(std, 1e-6)


def smooth_prediction(history: deque, labels: List[str]) -> Tuple[str, float]:
    if not history:
        return "-", 0.0
    classes = [item[0] for item in history]
    best_class, _ = Counter(classes).most_common(1)[0]
    confs = [c for cls, c in history if cls == best_class]
    confidence = float(np.mean(confs)) if confs else 0.0
    return labels[best_class], confidence


def main() -> int:
    args = parse_args()

    if tf is None:
        raise RuntimeError("TensorFlow is not installed. Install with: pip install tensorflow")
    if mp is None:
        raise RuntimeError("MediaPipe is not installed. Install with: pip install mediapipe")
    if cv2 is None:
        raise RuntimeError("OpenCV is not installed. Install with: pip install opencv-python")

    labels = load_labels(args.labels.resolve())
    mean, std = load_norm(args.norm.resolve())

    model_path = args.model.resolve()
    if not model_path.exists():
        raise FileNotFoundError(f"TFLite model not found: {model_path}")

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_info = interpreter.get_input_details()[0]
    output_info = interpreter.get_output_details()[0]

    if int(input_info["shape"][-1]) != LANDMARK_DIM:
        raise RuntimeError(
            f"Model expects input dim {input_info['shape'][-1]}, but LANDMARK_DIM={LANDMARK_DIM}. "
            "Re-train the model or check the --model path."
        )
    if int(output_info["shape"][-1]) != len(labels):
        raise RuntimeError(
            f"labels.txt has {len(labels)} entries but model output has {output_info['shape'][-1]}."
        )

    input_dtype = input_info["dtype"]
    input_buffer = np.zeros(input_info["shape"], dtype=input_dtype)

    # INT8 models store quantization params; float models have scale=0 (unused).
    input_scale, input_zero_point = input_info.get("quantization", (0.0, 0))
    is_int8_input = input_dtype == np.int8 and input_scale != 0.0

    output_scale, output_zero_point = output_info.get("quantization", (0.0, 0))
    is_int8_output = output_info["dtype"] == np.int8 and output_scale != 0.0

    cap = cv2.VideoCapture(args.camera_id)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open webcam (camera id {args.camera_id}).")

    pred_history: deque = deque(maxlen=max(1, args.history))
    frame_times: deque = deque(maxlen=60)
    extractor = DualHandLandmarkExtractor(task_model=args.hand_model)
    stable_seconds = max(0.1, float(args.stable_seconds))
    shown_label = "No hand"
    shown_conf = 0.0
    pending_label: str | None = None
    pending_since = 0.0

    print("Running - press ESC or 'q' to quit.", flush=True)

    try:
        while True:
            t0 = time.perf_counter()
            ok, frame = cap.read()
            if not ok:
                break

            if args.flip:
                frame = cv2.flip(frame, 1)

            features = extractor.extract(frame)
            if features is None:
                pred_history.clear()
                pending_label = None
                shown_label = "No hand"
                shown_conf = 0.0
                label_text = shown_label
                conf_text = f"{shown_conf:.2f}"
                lock_text = "Lock: no hand"
            else:
                features = (features - mean) / std

                if is_int8_input:
                    quantized = np.round(features / input_scale + input_zero_point).clip(-128, 127)
                    np.copyto(input_buffer[0], quantized.astype(np.int8, copy=False))
                else:
                    np.copyto(input_buffer[0], features.astype(input_dtype, copy=False))

                interpreter.set_tensor(input_info["index"], input_buffer)
                interpreter.invoke()
                raw_output = interpreter.get_tensor(output_info["index"])[0]

                if is_int8_output:
                    probs = (raw_output.astype(np.float32) - output_zero_point) * output_scale
                else:
                    probs = raw_output

                pred_idx = int(np.argmax(probs))
                pred_conf = float(probs[pred_idx])
                pred_history.append((pred_idx, pred_conf))

                smooth_label, smooth_conf = smooth_prediction(pred_history, labels)
                candidate_label = smooth_label if smooth_conf >= args.min_confidence else "Uncertain"
                now = time.perf_counter()

                if candidate_label == shown_label:
                    pending_label = None
                    pending_since = 0.0
                    shown_conf = smooth_conf
                    lock_text = f"Lock: {shown_label} stable"
                else:
                    if pending_label != candidate_label:
                        pending_label = candidate_label
                        pending_since = now
                    elapsed = now - pending_since
                    if elapsed >= stable_seconds:
                        shown_label = candidate_label
                        shown_conf = smooth_conf
                        pending_label = None
                        pending_since = 0.0
                        lock_text = f"Lock: switched to {shown_label}"
                    else:
                        lock_text = f"Lock: {candidate_label} {elapsed:.1f}/{stable_seconds:.1f}s"

                label_text = shown_label
                conf_text = f"{shown_conf:.2f}"

            frame_times.append(time.perf_counter() - t0)
            avg_frame_time = float(np.mean(frame_times)) if frame_times else 0.0
            fps = (1.0 / avg_frame_time) if avg_frame_time > 0 else 0.0

            cv2.putText(frame, f"Sign: {label_text}", (12, 35), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (40, 220, 40), 2)
            cv2.putText(frame, f"Conf: {conf_text}", (12, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 200, 40), 2)
            cv2.putText(frame, f"FPS : {fps:.1f}", (12, 100), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (70, 170, 255), 2)
            cv2.putText(frame, lock_text, (12, 130), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (180, 220, 255), 2)

            cv2.imshow("ISL Sign Classifier", frame)
            key = cv2.waitKey(1) & 0xFF
            if key == 27 or key == ord("q"):
                break
    finally:
        extractor.close()
        cap.release()
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

