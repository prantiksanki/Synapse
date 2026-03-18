"""
STEP 3 — Train LSTM model on the built dataset and export to TFLite.

Usage:
    python 3_train.py \
        --dataset dataset.npz \
        --epochs 50 \
        --batch_size 32 \
        --output_dir models/

Outputs:
    models/sign_model.h5        — full Keras model
    models/sign_model.tflite    — quantized TFLite model for mobile
    models/training_history.png — accuracy/loss curves
"""

import os
import json
import argparse
import numpy as np
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix

# Disable GPU if needed — set CUDA_VISIBLE_DEVICES=-1 before running
# os.environ["CUDA_VISIBLE_DEVICES"] = "-1"


# ── Model ────────────────────────────────────────────────────────────────────

def build_model(sequence_length: int, num_features: int, num_classes: int) -> tf.keras.Model:
    """
    LSTM classifier:
      Input  (30, 63)
      LSTM   128  → Dropout 0.3
      LSTM   64
      Dense  64 relu
      Dense  num_classes softmax
    """
    inputs = tf.keras.Input(shape=(sequence_length, num_features), name="landmarks")

    x = tf.keras.layers.LSTM(128, return_sequences=True, name="lstm_1")(inputs)
    x = tf.keras.layers.Dropout(0.3, name="drop_1")(x)

    x = tf.keras.layers.LSTM(64, return_sequences=False, name="lstm_2")(x)
    x = tf.keras.layers.Dropout(0.2, name="drop_2")(x)

    x = tf.keras.layers.Dense(64, activation="relu", name="dense_1")(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax", name="predictions")(x)

    model = tf.keras.Model(inputs, outputs, name="sign_lstm")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


# ── Training ─────────────────────────────────────────────────────────────────

def train(
    X: np.ndarray,
    Y: np.ndarray,
    classes: list[str],
    epochs: int,
    batch_size: int,
    output_dir: str,
):
    os.makedirs(output_dir, exist_ok=True)

    X_train, X_val, Y_train, Y_val = train_test_split(
        X, Y, test_size=0.15, random_state=42, stratify=Y.argmax(axis=1)
    )
    print(f"Train: {len(X_train)}  Val: {len(X_val)}  Classes: {len(classes)}")

    seq_len = X.shape[1]   # 30
    features = X.shape[2]  # 63

    model = build_model(seq_len, features, len(classes))
    model.summary()

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy", patience=10, restore_best_weights=True
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.5, patience=5, min_lr=1e-6, verbose=1
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=os.path.join(output_dir, "best_model.h5"),
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
        ),
    ]

    history = model.fit(
        X_train, Y_train,
        validation_data=(X_val, Y_val),
        epochs=epochs,
        batch_size=batch_size,
        callbacks=callbacks,
    )

    return model, history, X_val, Y_val


# ── Evaluation ───────────────────────────────────────────────────────────────

def evaluate(model, X_val, Y_val, classes, output_dir):
    Y_pred = model.predict(X_val, verbose=0)
    y_true = Y_val.argmax(axis=1)
    y_pred = Y_pred.argmax(axis=1)

    acc = (y_true == y_pred).mean()
    print(f"\nValidation Accuracy: {acc * 100:.2f}%\n")

    report = classification_report(y_true, y_pred, target_names=classes, zero_division=0)
    print(report)

    report_path = os.path.join(output_dir, "classification_report.txt")
    with open(report_path, "w") as f:
        f.write(report)
    print(f"Report saved → {report_path}")


# ── Plot ─────────────────────────────────────────────────────────────────────

def save_plot(history, output_dir):
    try:
        import matplotlib.pyplot as plt

        fig, axes = plt.subplots(1, 2, figsize=(12, 4))

        axes[0].plot(history.history["accuracy"],     label="train")
        axes[0].plot(history.history["val_accuracy"], label="val")
        axes[0].set_title("Accuracy")
        axes[0].legend()

        axes[1].plot(history.history["loss"],     label="train")
        axes[1].plot(history.history["val_loss"], label="val")
        axes[1].set_title("Loss")
        axes[1].legend()

        path = os.path.join(output_dir, "training_history.png")
        plt.tight_layout()
        plt.savefig(path)
        plt.close()
        print(f"Plot saved → {path}")
    except ImportError:
        print("matplotlib not installed — skipping plot.")


# ── TFLite export ─────────────────────────────────────────────────────────────

def export_tflite(model, output_dir: str):
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # LSTM uses TensorList ops — needs SELECT_TF_OPS to convert
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter._experimental_lower_tensor_list_ops = False
    tflite_model = converter.convert()

    path = os.path.join(output_dir, "sign_model.tflite")
    with open(path, "wb") as f:
        f.write(tflite_model)

    size_kb = os.path.getsize(path) / 1024
    print(f"TFLite model saved → {path}  ({size_kb:.1f} KB)")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Train LSTM sign language classifier")
    parser.add_argument("--dataset",    default="dataset.npz",  help="Path to dataset.npz")
    parser.add_argument("--epochs",     type=int, default=50,   help="Max training epochs")
    parser.add_argument("--batch_size", type=int, default=32,   help="Batch size")
    parser.add_argument("--output_dir", default="models",       help="Where to save outputs")
    args = parser.parse_args()

    # Load dataset
    print(f"Loading dataset: {args.dataset}")
    data = np.load(args.dataset, allow_pickle=True)
    X       = data["X"]
    Y       = data["Y"]
    classes = list(data["classes"])
    print(f"X: {X.shape}  Y: {Y.shape}  Classes: {len(classes)}")

    # Save labels alongside model
    os.makedirs(args.output_dir, exist_ok=True)
    labels_path = os.path.join(args.output_dir, "labels.json")
    with open(labels_path, "w") as f:
        json.dump(classes, f, indent=2)
    print(f"Labels saved → {labels_path}")

    # Train
    model, history, X_val, Y_val = train(
        X, Y, classes, args.epochs, args.batch_size, args.output_dir
    )

    # Save full Keras model
    h5_path = os.path.join(args.output_dir, "sign_model.h5")
    model.save(h5_path)
    print(f"Keras model saved → {h5_path}")

    # Evaluate
    evaluate(model, X_val, Y_val, classes, args.output_dir)

    # Plot
    save_plot(history, args.output_dir)

    # TFLite export
    export_tflite(model, args.output_dir)

    print("\nTraining complete.")


if __name__ == "__main__":
    main()
