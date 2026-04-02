import argparse
import json
import random
import time
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight

try:
    import tensorflow as tf
except ImportError:
    tf = None

# 21 landmarks x (x, y, z) x 2 hands = 126 features
LANDMARK_DIM = 126
LABELS_ORDER = [chr(c) for c in range(ord("A"), ord("Z") + 1)]  # A-Z, 26 classes


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Train lightweight ISL sign-language classifier from pre-extracted landmarks."
    )
    parser.add_argument(
        "--isl-csv",
        type=Path,
        default=script_dir / "collected_landmarks.csv",
        help="Path to the ISL landmarks CSV file.",
    )
    parser.add_argument(
        "--model-h5",
        type=Path,
        default=script_dir / "model.h5",
        help="Output Keras model path.",
    )
    parser.add_argument(
        "--model-tflite",
        type=Path,
        default=script_dir / "model.tflite",
        help="Output TFLite model path.",
    )
    parser.add_argument(
        "--labels",
        type=Path,
        default=script_dir / "labels.txt",
        help="Output labels file path.",
    )
    parser.add_argument(
        "--norm",
        type=Path,
        default=script_dir / "normalization.json",
        help="Saved normalization stats path.",
    )
    parser.add_argument("--val-split", type=float, default=0.2, help="Validation split ratio (stratified).")
    parser.add_argument("--seed", type=int, default=42, help="Random seed.")
    parser.add_argument("--epochs", type=int, default=60, help="Max epochs for first training pass.")
    parser.add_argument("--batch-size", type=int, default=128, help="Batch size.")
    parser.add_argument(
        "--quant",
        choices=["dynamic", "int8", "float16"],
        default="int8",
        help=(
            "TFLite quantization mode. "
            "'dynamic': weights-only (fast conversion, float activations). "
            "'int8': full integer quantization with calibration dataset (fastest on mobile NPU/DSP). "
            "'float16': half-precision weights (good GPU delegate speedup)."
        ),
    )
    parser.add_argument(
        "--calib-samples",
        type=int,
        default=200,
        help="Number of representative samples used for INT8 calibration (--quant int8 only).",
    )
    return parser.parse_args()


def set_seed(seed: int) -> None:
    if tf is None:
        raise RuntimeError("TensorFlow is not installed. Install with: pip install tensorflow")
    random.seed(seed)
    np.random.seed(seed)
    tf.random.set_seed(seed)


def load_isl_csv(csv_path: Path) -> Tuple[np.ndarray, np.ndarray, List[str]]:
    """
    Load the ISL Gesture Landmarks CSV.

    Columns: target, uses_two_hands, left_hand_x_0..z_20, right_hand_x_0..z_20
    target is an integer 0-25 mapping to A-Z.

    Returns x (N, 126), y (N,) int32, and the label list.
    """
    import pandas as pd

    print(f"Loading ISL landmarks CSV: {csv_path}", flush=True)
    df = pd.read_csv(csv_path)

    required = {"target", "uses_two_hands"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"CSV is missing required columns: {missing}")

    # Build feature columns in order: all left_hand then all right_hand,
    # each sorted as x_0,y_0,z_0, x_1,y_1,z_1 ... x_20,y_20,z_20
    left_cols = [f"left_hand_{ax}_{i}" for i in range(21) for ax in ("x", "y", "z")]
    right_cols = [f"right_hand_{ax}_{i}" for i in range(21) for ax in ("x", "y", "z")]
    feature_cols = left_cols + right_cols  # 63 + 63 = 126

    missing_feat = [c for c in feature_cols if c not in df.columns]
    if missing_feat:
        raise ValueError(f"CSV is missing landmark columns: {missing_feat[:5]}...")

    x = df[feature_cols].values.astype(np.float32)
    y_raw = df["target"].values.astype(np.int32)

    unique_targets = sorted(np.unique(y_raw).tolist())
    if len(unique_targets) < 2:
        raise ValueError(f"Need at least 2 classes, found: {unique_targets}")
    # Remap targets to a contiguous 0..N-1 range in case only a subset of
    # letters was collected (e.g. collect.py with --letters A B C).
    remap = {old: new for new, old in enumerate(unique_targets)}
    y_raw = np.array([remap[t] for t in y_raw], dtype=np.int32)
    labels = [LABELS_ORDER[t] for t in unique_targets]
    print(f"  Classes found : {len(unique_targets)} ({labels[0]}-{labels[-1]})", flush=True)

    # The dataset uses -1.0 as a sentinel for missing/absent hands.
    # Replace sentinel rows with zeros BEFORE wrist-relative subtraction so
    # absent hands are represented as an all-zero vector — matching what
    # predict.py sends when MediaPipe detects no hand on that side.
    sentinel = -1.0
    left_xyz  = x[:, :63].reshape(-1, 21, 3)   # (N, 21, 3)
    right_xyz = x[:, 63:].reshape(-1, 21, 3)   # (N, 21, 3)

    left_absent  = (left_xyz[:, 0, 0] == sentinel)   # wrist x == -1 → absent
    right_absent = (right_xyz[:, 0, 0] == sentinel)

    left_xyz[left_absent]   = 0.0
    right_xyz[right_absent] = 0.0

    # Wrist-relative normalisation per hand removes global translation.
    # Only applied to hands that are actually present (wrist subtraction on
    # all-zero rows is a no-op, but being explicit avoids silent bugs).
    left_xyz[~left_absent]  -= left_xyz[~left_absent,  0:1, :]
    right_xyz[~right_absent] -= right_xyz[~right_absent, 0:1, :]

    x = np.concatenate([left_xyz.reshape(-1, 63), right_xyz.reshape(-1, 63)], axis=1)

    absent_left_count  = left_absent.sum()
    absent_right_count = right_absent.sum()
    print(f"  Absent left hand  (zeroed): {absent_left_count}", flush=True)
    print(f"  Absent right hand (zeroed): {absent_right_count}", flush=True)

    print(f"  Rows loaded : {len(x)}", flush=True)
    print(f"  Features    : {x.shape[1]}", flush=True)

    uses_two = df["uses_two_hands"].values
    two_hand_classes = sorted(df[uses_two == 1.0]["target"].unique().tolist())
    one_hand_classes = sorted(df[uses_two == 0.0]["target"].unique().tolist())
    if two_hand_classes:
        print(f"  Two-hand signs : {[LABELS_ORDER[i] for i in two_hand_classes if i < len(LABELS_ORDER)]}", flush=True)
    if one_hand_classes:
        print(f"  One-hand signs : {[LABELS_ORDER[i] for i in one_hand_classes if i < len(LABELS_ORDER)]}", flush=True)

    return x, y_raw, labels


def normalize_train_val(
    x_train: np.ndarray, x_val: np.ndarray
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    mean = x_train.mean(axis=0, keepdims=True)
    std = x_train.std(axis=0, keepdims=True)
    std = np.maximum(std, 1e-6)
    return (
        ((x_train - mean) / std).astype(np.float32),
        ((x_val - mean) / std).astype(np.float32),
        mean,
        std,
    )


def compute_class_weight_if_needed(y_train: np.ndarray, num_classes: int) -> Dict[int, float] | None:
    counts = np.bincount(y_train, minlength=num_classes)
    non_zero = counts[counts > 0]
    if len(non_zero) == 0:
        return None
    imbalance_ratio = float(non_zero.max() / max(non_zero.min(), 1))
    if imbalance_ratio < 1.5:
        return None
    classes = np.arange(num_classes)
    weights = compute_class_weight(class_weight="balanced", classes=classes, y=y_train)
    return {int(i): float(w) for i, w in zip(classes, weights)}


def build_model(num_classes: int, variant: int = 1) -> "tf.keras.Model":
    """
    Two-layer MLP designed for 126-dim landmark input.
    Slightly wider than the old 42-dim version to capture two-hand relationships.
    """
    if variant == 1:
        hidden1, hidden2 = 128, 64
        dr1, dr2 = 0.25, 0.20
        lr = 1e-3
    else:
        hidden1, hidden2 = 160, 80
        dr1, dr2 = 0.30, 0.25
        lr = 7e-4

    model = tf.keras.Sequential(
        [
            tf.keras.layers.Input(shape=(LANDMARK_DIM,), name="landmarks"),
            tf.keras.layers.Dense(hidden1, activation="relu"),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Dropout(dr1),
            tf.keras.layers.Dense(hidden2, activation="relu"),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Dropout(dr2),
            tf.keras.layers.Dense(num_classes, activation="softmax"),
        ]
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=lr),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def train_once(
    model: "tf.keras.Model",
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_val: np.ndarray,
    y_val: np.ndarray,
    epochs: int,
    batch_size: int,
    class_weight: Dict[int, float] | None,
    patience: int,
) -> Tuple["tf.keras.Model", float]:
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy",
            patience=patience,
            restore_best_weights=True,
            mode="max",
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=max(2, patience // 3),
            min_lr=1e-5,
            verbose=1,
        ),
    ]
    history = model.fit(
        x_train,
        y_train,
        validation_data=(x_val, y_val),
        epochs=epochs,
        batch_size=batch_size,
        class_weight=class_weight,
        callbacks=callbacks,
        verbose=2,
    )
    best_val_acc = float(max(history.history.get("val_accuracy", [0.0])))
    return model, best_val_acc


def save_labels(labels_path: Path, labels: Sequence[str]) -> None:
    labels_path.parent.mkdir(parents=True, exist_ok=True)
    with labels_path.open("w", encoding="utf-8") as f:
        for label in labels:
            f.write(f"{label}\n")


def save_norm(norm_path: Path, mean: np.ndarray, std: np.ndarray) -> None:
    norm_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"mean": mean.flatten().tolist(), "std": std.flatten().tolist()}
    norm_path.write_text(json.dumps(payload), encoding="utf-8")


def convert_to_tflite(
    model: "tf.keras.Model",
    tflite_path: Path,
    sample: np.ndarray,
    expected_classes: int,
    quant: str = "int8",
    calib_data: np.ndarray | None = None,
) -> int:
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    if quant == "int8":
        if calib_data is None or len(calib_data) == 0:
            raise ValueError("INT8 quantization requires calibration data (calib_data must not be empty).")

        def representative_dataset():
            for row in calib_data:
                yield [row.reshape(1, LANDMARK_DIM).astype(np.float32)]

        converter.representative_dataset = representative_dataset
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.int8
        converter.inference_output_type = tf.int8

    elif quant == "float16":
        converter.target_spec.supported_types = [tf.float16]

    tflite_model = converter.convert()
    tflite_path.parent.mkdir(parents=True, exist_ok=True)
    tflite_path.write_bytes(tflite_model)

    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    input_info = interpreter.get_input_details()[0]
    output_info = interpreter.get_output_details()[0]

    input_dtype = input_info["dtype"]
    if quant == "int8":
        scale, zero_point = input_info["quantization"]
        input_tensor = (sample.reshape(1, LANDMARK_DIM) / scale + zero_point).astype(input_dtype)
    else:
        input_tensor = sample.reshape(1, LANDMARK_DIM).astype(input_dtype)

    interpreter.set_tensor(input_info["index"], input_tensor)
    interpreter.invoke()
    output = interpreter.get_tensor(output_info["index"])
    if output.shape[-1] != expected_classes:
        raise RuntimeError(
            f"TFLite output shape mismatch: got {output.shape}, expected classes={expected_classes}."
        )

    return tflite_path.stat().st_size


def estimate_latency_ms(model_path: Path, runs: int = 200) -> float:
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    x = np.zeros(inp["shape"], dtype=inp["dtype"])
    interpreter.set_tensor(inp["index"], x)
    t0 = time.perf_counter()
    for _ in range(runs):
        interpreter.invoke()
    return float((time.perf_counter() - t0) * 1000.0 / runs)


def main() -> int:
    args = parse_args()

    if tf is None:
        raise RuntimeError("TensorFlow is not installed. Install with: pip install tensorflow")

    set_seed(args.seed)

    csv_path = args.isl_csv.resolve()
    if not csv_path.exists():
        raise FileNotFoundError(f"ISL CSV not found: {csv_path}")

    x, y, labels = load_isl_csv(csv_path)
    num_classes = len(labels)

    save_labels(args.labels, labels)

    x_train, x_val, y_train, y_val = train_test_split(
        x, y,
        test_size=args.val_split,
        random_state=args.seed,
        stratify=y,
    )

    x_train_n, x_val_n, mean, std = normalize_train_val(x_train, x_val)
    save_norm(args.norm, mean, std)

    class_weight = compute_class_weight_if_needed(y_train, num_classes=num_classes)

    model1 = build_model(num_classes=num_classes, variant=1)
    model1.summary()
    model1, acc1 = train_once(
        model=model1,
        x_train=x_train_n,
        y_train=y_train,
        x_val=x_val_n,
        y_val=y_val,
        epochs=args.epochs,
        batch_size=args.batch_size,
        class_weight=class_weight,
        patience=8,
    )

    best_model = model1
    best_val_acc = acc1

    if best_val_acc < 0.95:
        print(f"\nVariant 1 val_accuracy={acc1:.4f} < 0.95, trying larger Variant 2...", flush=True)
        model2 = build_model(num_classes=num_classes, variant=2)
        model2, acc2 = train_once(
            model=model2,
            x_train=x_train_n,
            y_train=y_train,
            x_val=x_val_n,
            y_val=y_val,
            epochs=max(40, args.epochs),
            batch_size=args.batch_size,
            class_weight=class_weight,
            patience=10,
        )
        if acc2 > best_val_acc:
            best_model = model2
            best_val_acc = acc2

    args.model_h5.parent.mkdir(parents=True, exist_ok=True)
    best_model.save(args.model_h5)

    sample = x_val_n[0] if len(x_val_n) else x_train_n[0]

    rng = np.random.default_rng(args.seed)
    n_calib = min(args.calib_samples, len(x_train_n))
    calib_idx = rng.choice(len(x_train_n), size=n_calib, replace=False)
    calib_data = x_train_n[calib_idx]

    tflite_size = convert_to_tflite(
        best_model,
        args.model_tflite,
        sample,
        expected_classes=num_classes,
        quant=args.quant,
        calib_data=calib_data,
    )
    latency_ms = estimate_latency_ms(args.model_tflite)

    print("\n=== Training Summary ===")
    print(f"ISL CSV        : {csv_path}")
    print(f"Total samples  : {len(x)}")
    print(f"Classes        : {num_classes} ({labels[0]}-{labels[-1]})")
    print(f"Train / Val    : {len(x_train_n)} / {len(x_val_n)}")
    print(f"Val accuracy   : {best_val_acc:.4f}")
    print(f"Class weighting: {class_weight is not None}")
    print(f"Quantization   : {args.quant}" + (f" (calib samples: {n_calib})" if args.quant == "int8" else ""))
    print(f"TFLite size    : {tflite_size / 1024:.1f} KB")
    print(f"Latency (CPU)  : {latency_ms:.3f} ms")
    print(f"Saved model.h5 : {args.model_h5.resolve()}")
    print(f"Saved .tflite  : {args.model_tflite.resolve()}")
    print(f"Saved labels   : {args.labels.resolve()}")
    print(f"Saved norm     : {args.norm.resolve()}")

    if tflite_size >= 1024 * 1024:
        print("WARNING: TFLite model >= 1 MB. Consider reducing hidden units.")
    if latency_ms > 10.0:
        print("WARNING: Latency >10 ms on this machine; Android timing depends on hardware/NNAPI.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
