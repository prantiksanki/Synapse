"""
collect.py — Collect ISL landmark training data using your own webcam.

For each letter (A-Z) you hold the sign in front of the camera and press
SPACE to capture samples. The script saves landmarks extracted by the same
MediaPipe pipeline used at inference, so train/test distributions match.

Usage:
    python collect.py                        # collect all 26 letters
    python collect.py --letters A B C        # collect only specific letters
    python collect.py --resume               # add to existing CSV
    python collect.py --samples-per-class 200

Controls (per letter):
    SPACE  — capture one sample
    H      — hold: auto-capture every frame while held
    N      — skip to next letter
    Q/ESC  — quit and save
"""

import argparse
import csv
import time
from collections import deque
from pathlib import Path

import numpy as np

try:
    import cv2
except ImportError:
    raise SystemExit("OpenCV not installed. Run: pip install opencv-python")

try:
    import mediapipe as mp
except ImportError:
    raise SystemExit("MediaPipe not installed. Run: pip install mediapipe")

LABELS = [chr(c) for c in range(ord("A"), ord("Z") + 1)]
LANDMARK_DIM = 126  # 21 lm x (x,y,z) x 2 hands
CSV_HEADER = (
    ["target", "uses_two_hands"]
    + [f"left_hand_{ax}_{i}"  for i in range(21) for ax in ("x", "y", "z")]
    + [f"right_hand_{ax}_{i}" for i in range(21) for ax in ("x", "y", "z")]
)
SENTINEL = -1.0  # value written for absent hand (matches original dataset format)


# ── MediaPipe setup ───────────────────────────────────────────────────────────

def _make_extractor(task_model: Path | None):
    """Returns (mode, detector) using whichever MediaPipe API is available."""
    if hasattr(mp, "solutions"):
        det = mp.solutions.hands.Hands(
            static_image_mode=False,
            max_num_hands=2,
            model_complexity=0,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        return "solutions", det

    # Tasks API
    candidates = [task_model] if task_model else []
    script_dir = Path(__file__).resolve().parent
    candidates += [
        script_dir / "hand_landmarker.task",
        script_dir.parent / "hand_landmarker.task",
    ]
    model_path = next((p for p in candidates if p and p.exists()), None)
    if model_path is None:
        raise FileNotFoundError(
            "hand_landmarker.task not found. Place it in test/light_weight/ "
            "or pass --hand-model."
        )

    last_result = [None]

    def _cb(result, _img, _ts):
        last_result[0] = result

    vision = mp.tasks.vision
    opts = vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.LIVE_STREAM,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
        result_callback=_cb,
    )
    det = vision.HandLandmarker.create_from_options(opts)
    return "tasks", (det, last_result)


def _extract(frame_bgr, mode, detector, ts_counter: list):
    """
    Returns (left_xyz, right_xyz, found_any) where each xyz is (21,3) float32.
    Absent hand is all-zeros (wrist not yet subtracted here).
    """
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    left  = np.zeros((21, 3), dtype=np.float32)
    right = np.zeros((21, 3), dtype=np.float32)

    if mode == "solutions":
        frame_rgb.flags.writeable = False
        result = detector.process(frame_rgb)
        hand_lms_list  = result.multi_hand_landmarks  or []
        handedness_list = result.multi_handedness or []
        hands = [
            (h.classification[0].label, lm.landmark)
            for lm, h in zip(hand_lms_list, handedness_list)
        ]
    else:
        det, last_result = detector
        ts_counter[0] += 1
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
        det.detect_async(mp_img, ts_counter[0])
        result = last_result[0]
        if result is None or not result.hand_landmarks:
            return left, right, False
        hands = [
            (result.handedness[i][0].display_name, result.hand_landmarks[i])
            for i in range(len(result.hand_landmarks))
        ]

    if not hands:
        return left, right, False

    for label, lms in hands:
        coords = np.array([[lm.x, lm.y, lm.z] for lm in lms], dtype=np.float32)
        if label == "Left":
            left = coords
        else:
            right = coords

    # If only one hand detected put it in the LEFT slot — matches training convention
    left_present  = np.any(left  != 0)
    right_present = np.any(right != 0)
    if right_present and not left_present:
        left  = right
        right = np.zeros((21, 3), dtype=np.float32)

    return left, right, True


def _to_row(target_idx: int, left: np.ndarray, right: np.ndarray) -> list:
    """
    Build one CSV row.
    Applies wrist-relative subtraction to present hands.
    Absent hand (all zeros) is written as SENTINEL (-1.0) for the wrist x
    coordinate to match the original dataset format — train.py handles this.
    """
    left  = left.copy()
    right = right.copy()

    left_present  = np.any(left  != 0)
    right_present = np.any(right != 0)
    uses_two = 1 if (left_present and right_present) else 0

    if left_present:
        left -= left[0:1]   # wrist-relative
    else:
        left[0, 0] = SENTINEL  # mark as absent

    if right_present:
        right -= right[0:1]
    else:
        right[0, 0] = SENTINEL

    row = [target_idx, float(uses_two)]
    row += left.flatten().tolist()
    row += right.flatten().tolist()
    return row


# ── Drawing helpers ───────────────────────────────────────────────────────────

def _draw_ui(frame, letter, idx, total, captured, target, auto_capture):
    h, w = frame.shape[:2]
    # dark overlay bar at top
    cv2.rectangle(frame, (0, 0), (w, 110), (20, 20, 20), -1)

    status = "AUTO" if auto_capture else "MANUAL"
    color  = (0, 200, 80) if auto_capture else (80, 200, 255)

    cv2.putText(frame, f"Sign: {letter}  ({idx+1}/{total})",
                (12, 38), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (255, 255, 255), 2)
    cv2.putText(frame, f"Captured: {captured}/{target}  [{status}]",
                (12, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.75, color, 2)
    cv2.putText(frame, "SPACE=capture  H=hold  N=next  Q=quit",
                (12, 100), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (160, 160, 160), 1)


def _draw_landmarks(frame, left: np.ndarray, right: np.ndarray,
                    left_present: bool, right_present: bool):
    """Draw dots for detected hand landmarks (raw screen coords before wrist sub)."""
    h, w = frame.shape[:2]
    for coords, present, col in [
        (left,  left_present,  (80, 220, 80)),
        (right, right_present, (80, 160, 255)),
    ]:
        if not present:
            continue
        for i, (x, y, _) in enumerate(coords):
            px, py = int(x * w), int(y * h)
            cv2.circle(frame, (px, py), 4, col, -1)


# ── Main ──────────────────────────────────────────────────────────────────────

def parse_args():
    script_dir = Path(__file__).resolve().parent
    p = argparse.ArgumentParser(description="Collect ISL sign-language training data.")
    p.add_argument("--letters", nargs="+", default=LABELS,
                   help="Letters to collect (default: all A-Z).")
    p.add_argument("--samples-per-class", type=int, default=300,
                   help="Target number of samples per letter.")
    p.add_argument("--csv", type=Path,
                   default=script_dir / "collected_landmarks.csv",
                   help="Output CSV path.")
    p.add_argument("--resume", action="store_true",
                   help="Append to existing CSV instead of overwriting.")
    p.add_argument("--camera-id", type=int, default=0)
    p.add_argument("--flip", action="store_true",
                   help="Mirror webcam (natural selfie view).")
    p.add_argument("--hand-model", type=Path, default=None,
                   help="Path to hand_landmarker.task (Tasks API only).")
    return p.parse_args()


def main():
    args = parse_args()
    letters = [l.upper() for l in args.letters if l.upper() in LABELS]
    if not letters:
        raise SystemExit("No valid letters specified.")

    csv_path: Path = args.csv
    write_header = not (args.resume and csv_path.exists())
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    # Count already-collected samples per letter if resuming
    existing_counts = {l: 0 for l in letters}
    if args.resume and csv_path.exists():
        with csv_path.open("r", encoding="utf-8") as f:
            reader = csv.reader(f)
            next(reader, None)  # skip header
            for row in reader:
                if row:
                    t = int(row[0])
                    lbl = LABELS[t] if 0 <= t < len(LABELS) else None
                    if lbl in existing_counts:
                        existing_counts[lbl] += 1
        print("Resuming. Existing counts:", existing_counts)

    cap = cv2.VideoCapture(args.camera_id)
    if not cap.isOpened():
        raise SystemExit(f"Cannot open camera {args.camera_id}.")

    mode, detector = _make_extractor(args.hand_model)
    print(f"MediaPipe mode: {mode}")
    ts_counter = [0]

    file_mode = "a" if (args.resume and csv_path.exists()) else "w"
    csv_file  = csv_path.open(file_mode, newline="", encoding="utf-8")
    writer    = csv.writer(csv_file)
    if write_header:
        writer.writerow(CSV_HEADER)

    total_written = 0
    try:
        for idx, letter in enumerate(letters):
            target_idx  = LABELS.index(letter)
            captured    = existing_counts.get(letter, 0)
            need        = args.samples_per_class - captured
            if need <= 0:
                print(f"  {letter}: already have {captured} samples, skipping.")
                continue

            print(f"\n>>> Show sign for '{letter}' — need {need} more samples")
            auto_capture = False
            last_auto_ts = 0.0

            while captured < args.samples_per_class:
                ok, frame = cap.read()
                if not ok:
                    break
                if args.flip:
                    frame = cv2.flip(frame, 1)

                left, right, found = _extract(frame, mode, detector, ts_counter)
                left_present  = np.any(left  != 0)
                right_present = np.any(right != 0)

                _draw_landmarks(frame, left, right, left_present, right_present)
                _draw_ui(frame, letter, idx, len(letters),
                         captured, args.samples_per_class, auto_capture)

                # Progress bar
                bar_w = int((frame.shape[1] - 24) * captured / args.samples_per_class)
                cv2.rectangle(frame, (12, frame.shape[0]-18),
                              (12 + bar_w, frame.shape[0]-8), (0, 200, 80), -1)

                cv2.imshow("ISL Data Collector", frame)
                key = cv2.waitKey(1) & 0xFF

                if key == 27 or key == ord("q"):
                    print("\nQuitting early — data saved.")
                    return

                if key == ord("n"):
                    print(f"  {letter}: skipped with {captured} samples.")
                    break

                if key == ord("h"):
                    auto_capture = not auto_capture
                    print(f"  Auto-capture {'ON' if auto_capture else 'OFF'}")

                should_capture = (key == ord(" ")) or (
                    auto_capture and found and (time.perf_counter() - last_auto_ts) > 0.05
                )

                if should_capture and found:
                    row = _to_row(target_idx, left, right)
                    writer.writerow(row)
                    csv_file.flush()
                    captured += 1
                    total_written += 1
                    last_auto_ts = time.perf_counter()

            print(f"  {letter}: {captured} samples collected.")

    finally:
        csv_file.close()
        if hasattr(detector, "close"):
            detector.close()
        elif isinstance(detector, tuple):
            detector[0].close()
        cap.release()
        cv2.destroyAllWindows()

    print(f"\nDone. Total new samples written: {total_written}")
    print(f"CSV saved to: {csv_path.resolve()}")
    print(f"\nNext step — train with your collected data:")
    print(f"  python train.py --isl-csv \"{csv_path.resolve()}\"")


if __name__ == "__main__":
    main()
