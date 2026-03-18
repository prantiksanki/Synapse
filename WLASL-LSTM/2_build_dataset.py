"""
STEP 2 — Load saved .npy sequences and build X, Y arrays for training.

Usage:
    python 2_build_dataset.py \
        --data_dir MP_Data \
        --sequence_length 30 \
        --output_file dataset.npz

Output:
    dataset.npz  →  X shape (N, 30, 63),  Y shape (N, num_classes)
"""

import os
import json
import argparse
import numpy as np
from tqdm import tqdm


def load_dataset(data_dir: str, sequence_length: int) -> tuple[np.ndarray, np.ndarray, list[str]]:
    """
    Walks data_dir/<label>/<seq_id>/<frame>.npy and builds:
      X: (N, sequence_length, 63)
      Y: (N,)  — integer class indices
    """
    labels_path = os.path.join(data_dir, "labels.json")
    if os.path.exists(labels_path):
        with open(labels_path) as f:
            classes = json.load(f)
    else:
        classes = sorted([
            d for d in os.listdir(data_dir)
            if os.path.isdir(os.path.join(data_dir, d))
        ])

    label_map = {label: i for i, label in enumerate(classes)}

    sequences, labels = [], []

    for label in tqdm(classes, desc="Loading sequences"):
        label_dir = os.path.join(data_dir, label)
        if not os.path.isdir(label_dir):
            continue

        for seq_id in sorted(os.listdir(label_dir)):
            seq_dir = os.path.join(label_dir, seq_id)
            if not os.path.isdir(seq_dir):
                continue

            frames = []
            for frame_i in range(sequence_length):
                npy_path = os.path.join(seq_dir, f"{frame_i}.npy")
                if os.path.exists(npy_path):
                    frames.append(np.load(npy_path))
                else:
                    frames.append(np.zeros(63, dtype=np.float32))

            sequences.append(frames)
            labels.append(label_map[label])

    X = np.array(sequences, dtype=np.float32)           # (N, T, 63)
    Y = np.array(labels, dtype=np.int32)                 # (N,)

    return X, Y, classes


def one_hot(Y: np.ndarray, num_classes: int) -> np.ndarray:
    out = np.zeros((len(Y), num_classes), dtype=np.float32)
    out[np.arange(len(Y)), Y] = 1.0
    return out


def print_stats(X: np.ndarray, Y: np.ndarray, classes: list[str]):
    print(f"\nDataset stats:")
    print(f"  Total sequences : {len(X)}")
    print(f"  Shape X         : {X.shape}")
    print(f"  Num classes     : {len(classes)}")
    counts = np.bincount(Y)
    print(f"  Min per class   : {counts.min()}")
    print(f"  Max per class   : {counts.max()}")
    print(f"  Mean per class  : {counts.mean():.1f}")


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Build training dataset from .npy sequences")
    parser.add_argument("--data_dir",        default="MP_Data",      help="Root of extracted sequences")
    parser.add_argument("--sequence_length", type=int, default=30,   help="Frames per sequence")
    parser.add_argument("--output_file",     default="dataset.npz",  help="Output .npz file path")
    args = parser.parse_args()

    print(f"Loading from: {args.data_dir}")
    X, Y, classes = load_dataset(args.data_dir, args.sequence_length)

    print_stats(X, Y, classes)

    Y_onehot = one_hot(Y, len(classes))

    np.savez_compressed(
        args.output_file,
        X=X,
        Y=Y_onehot,
        Y_int=Y,
        classes=np.array(classes),
    )
    print(f"\nSaved → {args.output_file}")
    print(f"  X: {X.shape}  Y: {Y_onehot.shape}")


if __name__ == "__main__":
    main()
