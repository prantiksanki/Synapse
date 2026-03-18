"""
PIPELINE TEST — Generates dummy data and runs the full pipeline:
  dummy data -> dataset.npz -> train LSTM -> save model -> TFLite export -> mock inference

No camera or WLASL videos needed. Run with:
    python test_pipeline.py
"""

import os
import json
import time
import numpy as np
import tensorflow as tf
from sklearn.model_selection import train_test_split

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"   # suppress TF info logs


# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
NUM_CLASSES     = 10          # 10 dummy signs
SEQUENCE_LENGTH = 30          # 30 frames per sign
FEATURES        = 63          # 21 landmarks x 3 (x,y,z)
SAMPLES_PER_CLASS = 40        # 40 sequences per sign
EPOCHS          = 15          # quick test
BATCH_SIZE      = 16
THRESHOLD       = 0.5
OUTPUT_DIR      = "test_output"

DUMMY_SIGNS = [
    "hello", "thanks", "iloveyou", "help", "please",
    "yes",   "no",     "sorry",    "good", "bad"
]


# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Generate dummy landmark sequences
# ─────────────────────────────────────────────────────────────────────────────
def make_dummy_data():
    print("\n" + "="*60)
    print("STEP 1 — Generating dummy landmark sequences")
    print("="*60)

    # Each class gets a unique "base pattern" so the model can actually learn
    np.random.seed(42)
    class_bases = np.random.randn(NUM_CLASSES, FEATURES).astype(np.float32)

    X, Y = [], []
    for class_id in range(NUM_CLASSES):
        base = class_bases[class_id]
        for _ in range(SAMPLES_PER_CLASS):
            # Sequence: base pattern + small temporal variation + noise
            seq = []
            for t in range(SEQUENCE_LENGTH):
                noise     = np.random.randn(FEATURES).astype(np.float32) * 0.05
                temporal  = np.sin(t / SEQUENCE_LENGTH * np.pi) * 0.1
                frame     = base + noise + temporal
                seq.append(frame)
            X.append(seq)
            Y.append(class_id)

    X = np.array(X, dtype=np.float32)   # (400, 30, 63)
    Y = np.array(Y, dtype=np.int32)     # (400,)

    # One-hot
    Y_onehot = np.zeros((len(Y), NUM_CLASSES), dtype=np.float32)
    Y_onehot[np.arange(len(Y)), Y] = 1.0

    print(f"  X shape : {X.shape}  (samples x frames x features)")
    print(f"  Y shape : {Y_onehot.shape}  (one-hot)")
    print(f"  Classes : {DUMMY_SIGNS}")
    print(f"  Samples per class: {SAMPLES_PER_CLASS}")

    # Save dataset.npz
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    npz_path = os.path.join(OUTPUT_DIR, "dataset.npz")
    np.savez_compressed(
        npz_path,
        X=X,
        Y=Y_onehot,
        Y_int=Y,
        classes=np.array(DUMMY_SIGNS),
    )
    print(f"\n  Saved -> {npz_path}")
    return X, Y_onehot, Y


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Build LSTM model
# ─────────────────────────────────────────────────────────────────────────────
def build_model():
    print("\n" + "="*60)
    print("STEP 2 — Building LSTM model")
    print("="*60)

    inputs = tf.keras.Input(shape=(SEQUENCE_LENGTH, FEATURES), name="landmarks")
    x = tf.keras.layers.LSTM(128, return_sequences=True, name="lstm_1")(inputs)
    x = tf.keras.layers.Dropout(0.3, name="drop_1")(x)
    x = tf.keras.layers.LSTM(64, return_sequences=False, name="lstm_2")(x)
    x = tf.keras.layers.Dropout(0.2, name="drop_2")(x)
    x = tf.keras.layers.Dense(64, activation="relu", name="dense_1")(x)
    outputs = tf.keras.layers.Dense(NUM_CLASSES, activation="softmax", name="predictions")(x)

    model = tf.keras.Model(inputs, outputs, name="sign_lstm")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary()
    return model


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Train
# ─────────────────────────────────────────────────────────────────────────────
def train_model(model, X, Y_onehot):
    print("\n" + "="*60)
    print("STEP 3 — Training")
    print("="*60)

    X_train, X_val, Y_train, Y_val = train_test_split(
        X, Y_onehot, test_size=0.2, random_state=42
    )
    print(f"  Train: {len(X_train)}  Val: {len(X_val)}")

    t0 = time.time()
    history = model.fit(
        X_train, Y_train,
        validation_data=(X_val, Y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        verbose=1,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor="val_accuracy", patience=5, restore_best_weights=True, verbose=1
            )
        ]
    )
    elapsed = time.time() - t0

    final_train_acc = history.history["accuracy"][-1]
    final_val_acc   = history.history["val_accuracy"][-1]
    print(f"\n  Training time    : {elapsed:.1f}s")
    print(f"  Final train acc  : {final_train_acc*100:.1f}%")
    print(f"  Final val acc    : {final_val_acc*100:.1f}%")

    return model, X_val, Y_val


# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Save model + labels
# ─────────────────────────────────────────────────────────────────────────────
def save_model(model):
    print("\n" + "="*60)
    print("STEP 4 — Saving model")
    print("="*60)

    h5_path = os.path.join(OUTPUT_DIR, "sign_model.h5")
    model.save(h5_path)
    print(f"  Keras model -> {h5_path}")

    labels_path = os.path.join(OUTPUT_DIR, "labels.json")
    with open(labels_path, "w") as f:
        json.dump(DUMMY_SIGNS, f, indent=2)
    print(f"  Labels      -> {labels_path}")


# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — Export TFLite
# ─────────────────────────────────────────────────────────────────────────────
def export_tflite(model):
    print("\n" + "="*60)
    print("STEP 5 — TFLite export")
    print("="*60)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # LSTM uses TensorList ops — needs SELECT_TF_OPS to convert
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter._experimental_lower_tensor_list_ops = False
    tflite_bytes = converter.convert()

    tflite_path = os.path.join(OUTPUT_DIR, "sign_model.tflite")
    with open(tflite_path, "wb") as f:
        f.write(tflite_bytes)

    size_kb = os.path.getsize(tflite_path) / 1024
    print(f"  TFLite model -> {tflite_path}  ({size_kb:.1f} KB)")
    return tflite_path


# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Mock real-time inference (no webcam needed)
# ─────────────────────────────────────────────────────────────────────────────
def mock_realtime_inference(model, X_val, Y_val):
    print("\n" + "="*60)
    print("STEP 6 — Mock real-time inference (simulating webcam frames)")
    print("="*60)

    print(f"  Simulating 5 sign detections...\n")

    correct = 0
    for i in range(5):
        true_label_idx  = int(np.argmax(Y_val[i]))
        true_label      = DUMMY_SIGNS[true_label_idx]

        # Feed frame-by-frame like a real webcam would
        sequence_buffer = []
        for frame in X_val[i]:
            sequence_buffer.append(frame)
            if len(sequence_buffer) == SEQUENCE_LENGTH:
                inp   = np.array(sequence_buffer, dtype=np.float32)[np.newaxis]
                probs = model.predict(inp, verbose=0)[0]
                pred_idx    = int(np.argmax(probs))
                pred_label  = DUMMY_SIGNS[pred_idx]
                confidence  = float(probs[pred_idx])

                hit = "[OK]" if pred_label == true_label else "[X]"
                if pred_label == true_label:
                    correct += 1
                print(f"  [{hit}] True: {true_label:<12}  Predicted: {pred_label:<12}  Confidence: {confidence:.1%}")
                break

    print(f"\n  Result: {correct}/5 correct")


# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — Full evaluation on all validation samples
# ─────────────────────────────────────────────────────────────────────────────
def full_evaluation(model, X_val, Y_val):
    print("\n" + "="*60)
    print("STEP 7 — Full validation evaluation")
    print("="*60)

    preds = model.predict(X_val, verbose=0)
    y_true = np.argmax(Y_val, axis=1)
    y_pred = np.argmax(preds,  axis=1)

    acc = (y_true == y_pred).mean()
    print(f"\n  Validation accuracy: {acc*100:.2f}%\n")

    print("  Per-class results:")
    print(f"  {'Sign':<14} {'Correct':>8}  {'Total':>6}  {'Acc':>6}")
    print("  " + "-"*40)

    counts = np.bincount(y_true, minlength=NUM_CLASSES)
    for cls_i, sign in enumerate(DUMMY_SIGNS):
        mask    = y_true == cls_i
        total   = mask.sum()
        correct = (y_pred[mask] == cls_i).sum()
        cls_acc = correct / total if total > 0 else 0
        bar     = "|" * int(cls_acc * 10)
        print(f"  {sign:<14} {correct:>8}  {total:>6}  {cls_acc:>5.0%}  {bar}")


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
def main():
    print("\n" + "#"*60)
    print("  WLASL-LSTM PIPELINE TEST (Dummy Data)")
    print("#"*60)
    print(f"  Signs        : {NUM_CLASSES}")
    print(f"  Sequence len : {SEQUENCE_LENGTH} frames")
    print(f"  Features     : {FEATURES}  (21 landmarks x 3)")
    print(f"  Samples      : {NUM_CLASSES * SAMPLES_PER_CLASS} total  ({SAMPLES_PER_CLASS}/class)")
    print(f"  Epochs       : {EPOCHS}")

    # Run pipeline
    X, Y_onehot, Y_int = make_dummy_data()
    model               = build_model()
    model, X_val, Y_val = train_model(model, X, Y_onehot)

    save_model(model)
    tflite_path = export_tflite(model)

    mock_realtime_inference(model, X_val, Y_val)
    full_evaluation(model, X_val, Y_val)

    print("\n" + "="*60)
    print("PIPELINE TEST COMPLETE — No errors.")
    print("="*60)
    print(f"\nOutput files in '{OUTPUT_DIR}/':")
    for f in os.listdir(OUTPUT_DIR):
        size = os.path.getsize(os.path.join(OUTPUT_DIR, f))
        print(f"  {f:<30} {size/1024:.1f} KB")

    print("""
----------------------------------------------------------
NEXT STEPS (with real WLASL data):
  1. python 1_extract_landmarks.py --wlasl_dir WLASL/videos --num_classes 100
  2. python 2_build_dataset.py
  3. python 3_train.py --epochs 50
  4. python 4_app.py --model models/sign_model.h5
----------------------------------------------------------
""")


if __name__ == "__main__":
    main()
