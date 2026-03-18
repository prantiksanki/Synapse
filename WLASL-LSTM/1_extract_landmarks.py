"""
STEP 1 — Extract MediaPipe hand landmarks from WLASL (Kaggle processed) videos.

Dataset: https://www.kaggle.com/datasets/risangbaskoro/wlasl-processed
Expected dataset structure after download + unzip:
    WLASL_v0.3/
        WLASL_v0.3.json        <-- metadata mapping glosses to video IDs
        videos/
            00000.mp4
            00001.mp4
            ...

Usage:
    python 1_extract_landmarks.py \
        --dataset_dir path/to/WLASL_v0.3 \
        --output_dir MP_Data \
        --num_classes 100 \
        --sequence_length 30

Output structure:
    MP_Data/
        hello/
            0/  (sequence 0)
                0.npy ... 29.npy
            1/
                ...
        thanks/
            ...
"""

import os
import cv2
import json
import argparse
import urllib.request
import numpy as np
import mediapipe as mp
from tqdm import tqdm

# ── MediaPipe new API (0.10+) ─────────────────────────────────────────────────
BaseOptions        = mp.tasks.BaseOptions
HandLandmarker     = mp.tasks.vision.HandLandmarker
HandLandmarkerOpts = mp.tasks.vision.HandLandmarkerOptions
RunningMode        = mp.tasks.vision.RunningMode

MODEL_PATH = os.path.join(os.path.dirname(__file__), "hand_landmarker.task")
MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"


def ensure_model():
    """Download hand_landmarker.task if not present."""
    if not os.path.exists(MODEL_PATH):
        print(f"Downloading MediaPipe hand landmarker model...")
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
    )
    return HandLandmarker.create_from_options(opts)


def get_hand_landmarks(frame: np.ndarray, detector: HandLandmarker) -> np.ndarray:
    """
    Returns a (63,) array of x,y,z for the first detected hand.
    Returns zeros if no hand detected.
    """
    rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result   = detector.detect(mp_image)

    if result.hand_landmarks:
        lm = result.hand_landmarks[0]   # list of 21 NormalizedLandmark
        return np.array([[p.x, p.y, p.z] for p in lm], dtype=np.float32).flatten()

    return np.zeros(63, dtype=np.float32)


def normalize_landmarks(landmarks: np.ndarray) -> np.ndarray:
    """
    Normalize relative to wrist (landmark 0), scale by wrist->middle-MCP (landmark 9).
    Makes gesture position + scale invariant.
    """
    pts   = landmarks.reshape(21, 3)
    pts  -= pts[0].copy()                       # translate to wrist origin
    scale = np.linalg.norm(pts[9])              # distance wrist -> middle MCP
    if scale > 1e-6:
        pts /= scale
    return pts.flatten()


def extract_sequences_from_video(
    video_path: str,
    detector: HandLandmarker,
    sequence_length: int = 30,
) -> list:
    """
    Extracts up to 3 non-overlapping sequences of `sequence_length` normalized
    landmark frames from a video. Returns list of (sequence_length, 63) arrays.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    frames_landmarks = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        raw = get_hand_landmarks(frame, detector)
        frames_landmarks.append(normalize_landmarks(raw))

    cap.release()

    total = len(frames_landmarks)
    if total == 0:
        return []

    sequences = []
    if total < sequence_length:
        pad = [np.zeros(63, dtype=np.float32)] * (sequence_length - total)
        sequences.append(np.array(frames_landmarks + pad, dtype=np.float32))
    else:
        step = max(1, (total - sequence_length) // 2)
        for start in range(0, total - sequence_length + 1, step):
            sequences.append(
                np.array(frames_landmarks[start: start + sequence_length], dtype=np.float32)
            )
            if len(sequences) >= 3:
                break

    return sequences


def load_wlasl_classes(dataset_dir: str, num_classes: int) -> dict:
    """
    Reads WLASL_v0.3.json and maps each gloss to its video file paths.

    JSON structure:
      [{"gloss": "hello", "instances": [{"video_id": "00000"}, ...]}, ...]

    Returns {gloss: [video_path, ...]}
    """
    json_path  = os.path.join(dataset_dir, "WLASL_v0.3.json")
    videos_dir = os.path.join(dataset_dir, "videos")

    if not os.path.exists(json_path):
        raise FileNotFoundError(
            f"WLASL_v0.3.json not found in '{dataset_dir}'.\n"
            "Point --dataset_dir at the unzipped WLASL_v0.3 folder."
        )
    if not os.path.isdir(videos_dir):
        raise FileNotFoundError(f"'videos/' folder not found inside '{dataset_dir}'.")

    with open(json_path, "r") as f:
        wlasl_data = json.load(f)

    sign_to_videos = {}
    for entry in wlasl_data[:num_classes]:
        gloss     = entry["gloss"]
        video_ids = [inst["video_id"] for inst in entry.get("instances", [])]
        paths     = [
            os.path.join(videos_dir, f"{vid_id}.mp4")
            for vid_id in video_ids
            if os.path.exists(os.path.join(videos_dir, f"{vid_id}.mp4"))
        ]
        if paths:
            sign_to_videos[gloss] = paths
        else:
            print(f"  [SKIP] '{gloss}' — no video files found on disk")

    if not sign_to_videos:
        raise FileNotFoundError(
            f"No videos matched. Check '{videos_dir}' has .mp4 files matching WLASL_v0.3.json."
        )

    return sign_to_videos


def save_sequences(sign_to_videos: dict, output_dir: str, sequence_length: int) -> list:
    """Processes all videos, saves .npy frame files, returns sorted class list."""
    os.makedirs(output_dir, exist_ok=True)
    classes = sorted(sign_to_videos.keys())

    with make_detector() as detector:
        for label in classes:
            label_dir = os.path.join(output_dir, label)
            os.makedirs(label_dir, exist_ok=True)
            seq_idx = 0

            for video_path in tqdm(sign_to_videos[label], desc=f"[{label}]"):
                for seq in extract_sequences_from_video(video_path, detector, sequence_length):
                    seq_dir = os.path.join(label_dir, str(seq_idx))
                    os.makedirs(seq_dir, exist_ok=True)
                    for frame_i, frame_lm in enumerate(seq):
                        np.save(os.path.join(seq_dir, f"{frame_i}.npy"), frame_lm)
                    seq_idx += 1

    return classes


def save_labels(classes: list, output_dir: str):
    path = os.path.join(output_dir, "labels.json")
    with open(path, "w") as f:
        json.dump(classes, f, indent=2)
    print(f"Labels saved -> {path}")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Extract WLASL landmarks (MediaPipe 0.10+)")
    parser.add_argument(
        "--dataset_dir", required=True,
        help="Path to unzipped WLASL_v0.3 folder (contains WLASL_v0.3.json and videos/)"
    )
    parser.add_argument("--output_dir",      default="MP_Data", help="Where to save .npy sequences")
    parser.add_argument("--num_classes",     type=int, default=100, help="Top-N classes from JSON")
    parser.add_argument("--sequence_length", type=int, default=30,  help="Frames per sequence")
    args = parser.parse_args()

    print(f"\nDataset dir : {args.dataset_dir}")
    print(f"Output dir  : {args.output_dir}")
    print(f"Num classes : {args.num_classes}")
    print(f"Seq length  : {args.sequence_length} frames\n")

    sign_to_videos = load_wlasl_classes(args.dataset_dir, args.num_classes)
    print(f"Loaded {len(sign_to_videos)} classes with videos.\n")

    classes = save_sequences(sign_to_videos, args.output_dir, args.sequence_length)
    save_labels(classes, args.output_dir)

    print(f"\nDone. Data saved to '{args.output_dir}/'")
    print(f"Classes ({len(classes)}): {classes[:10]}{'...' if len(classes) > 10 else ''}")


if __name__ == "__main__":
    main()
