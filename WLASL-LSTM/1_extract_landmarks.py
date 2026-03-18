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
import numpy as np
import mediapipe as mp
from tqdm import tqdm

# ── MediaPipe setup ──────────────────────────────────────────────────────────
mp_hands = mp.solutions.hands


def get_hand_landmarks(frame: np.ndarray, hands_model) -> np.ndarray:
    """
    Returns a (63,) array of x,y,z for the first detected hand.
    Returns zeros if no hand detected.
    """
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    rgb.flags.writeable = False
    results = hands_model.process(rgb)

    if results.multi_hand_landmarks:
        lm = results.multi_hand_landmarks[0].landmark
        return np.array([[p.x, p.y, p.z] for p in lm], dtype=np.float32).flatten()

    return np.zeros(63, dtype=np.float32)


def normalize_landmarks(landmarks: np.ndarray) -> np.ndarray:
    """
    Normalize landmarks relative to wrist (landmark 0).
    Scale by distance from wrist to middle-finger MCP (landmark 9).
    Makes gesture position + scale invariant.
    """
    pts = landmarks.reshape(21, 3)
    wrist = pts[0].copy()
    pts -= wrist                          # translate to wrist origin

    scale = np.linalg.norm(pts[9])        # distance wrist -> middle MCP
    if scale > 1e-6:
        pts /= scale                      # normalize scale

    return pts.flatten()


def extract_sequences_from_video(
    video_path: str,
    hands_model,
    sequence_length: int = 30,
) -> list[np.ndarray]:
    """
    Extracts non-overlapping sequences of `sequence_length` normalized
    landmark frames from a video file.
    Returns a list of (sequence_length, 63) arrays.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    frames_landmarks = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        raw = get_hand_landmarks(frame, hands_model)
        frames_landmarks.append(normalize_landmarks(raw))

    cap.release()

    sequences = []
    total = len(frames_landmarks)

    if total < sequence_length:
        # Pad with zeros at the end if video is too short
        pad = [np.zeros(63, dtype=np.float32)] * (sequence_length - total)
        sequences.append(frames_landmarks + pad)
    else:
        # Slide window — take up to 3 non-overlapping sequences per video
        step = max(1, (total - sequence_length) // 2)
        for start in range(0, total - sequence_length + 1, step):
            sequences.append(frames_landmarks[start : start + sequence_length])
            if len(sequences) >= 3:
                break

    return [np.array(s, dtype=np.float32) for s in sequences]


def load_wlasl_classes(dataset_dir: str, num_classes: int) -> dict[str, list[str]]:
    """
    Reads WLASL_v0.3.json from dataset_dir and maps each gloss (sign label)
    to a list of video file paths under dataset_dir/videos/.

    JSON structure:
      [
        {
          "gloss": "hello",
          "instances": [
            {"video_id": "00000", ...},
            ...
          ]
        },
        ...
      ]

    Returns {gloss: [video_path, ...]}
    """
    json_path   = os.path.join(dataset_dir, "WLASL_v0.3.json")
    videos_dir  = os.path.join(dataset_dir, "videos")

    if not os.path.exists(json_path):
        raise FileNotFoundError(
            f"WLASL_v0.3.json not found in '{dataset_dir}'.\n"
            "Make sure you point --dataset_dir at the unzipped WLASL_v0.3 folder."
        )
    if not os.path.isdir(videos_dir):
        raise FileNotFoundError(
            f"'videos/' folder not found inside '{dataset_dir}'."
        )

    with open(json_path, "r") as f:
        wlasl_data = json.load(f)

    sign_to_videos: dict[str, list[str]] = {}

    for entry in wlasl_data[:num_classes]:          # limit to num_classes glosses
        gloss     = entry["gloss"]
        video_ids = [inst["video_id"] for inst in entry.get("instances", [])]

        paths = []
        for vid_id in video_ids:
            # video files are named <video_id>.mp4
            candidate = os.path.join(videos_dir, f"{vid_id}.mp4")
            if os.path.exists(candidate):
                paths.append(candidate)

        if paths:
            sign_to_videos[gloss] = paths
        else:
            print(f"  [SKIP] '{gloss}' — no video files found on disk")

    if not sign_to_videos:
        raise FileNotFoundError(
            f"No videos found. Check that '{videos_dir}' contains .mp4 files "
            "matching the video_ids in WLASL_v0.3.json."
        )

    return sign_to_videos


def save_sequences(
    sign_to_videos: dict[str, list[str]],
    output_dir: str,
    sequence_length: int,
) -> list[str]:
    """
    Processes all videos, saves .npy frame files, returns sorted class list.
    """
    os.makedirs(output_dir, exist_ok=True)
    classes = sorted(sign_to_videos.keys())

    with mp_hands.Hands(
        static_image_mode=False,
        max_num_hands=1,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as hands:
        for label in classes:
            label_dir = os.path.join(output_dir, label)
            os.makedirs(label_dir, exist_ok=True)

            seq_idx = 0
            for video_path in tqdm(sign_to_videos[label], desc=f"[{label}]"):
                sequences = extract_sequences_from_video(
                    video_path, hands, sequence_length
                )
                for seq in sequences:
                    seq_dir = os.path.join(label_dir, str(seq_idx))
                    os.makedirs(seq_dir, exist_ok=True)
                    for frame_i, frame_lm in enumerate(seq):
                        np.save(os.path.join(seq_dir, f"{frame_i}.npy"), frame_lm)
                    seq_idx += 1

    return classes


def save_labels(classes: list[str], output_dir: str):
    path = os.path.join(output_dir, "labels.json")
    with open(path, "w") as f:
        json.dump(classes, f, indent=2)
    print(f"Labels saved -> {path}")


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Extract WLASL landmarks")
    parser.add_argument(
        "--dataset_dir", required=True,
        help="Path to unzipped WLASL_v0.3 folder (must contain WLASL_v0.3.json and videos/)"
    )
    parser.add_argument("--output_dir",      default="MP_Data",  help="Where to save .npy sequences")
    parser.add_argument("--num_classes",     type=int, default=100, help="Number of sign classes (top-N from JSON)")
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
