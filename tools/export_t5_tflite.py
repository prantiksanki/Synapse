"""
Export T5-small grammar correction model to TFLite for Android.

Model used: vennify/t5-base-grammar-correction  (or t5-small fine-tuned on JFLEG/CoLA)
We use the smaller "prithivida/grammar_error_correcter_v1" which is T5-small based.

Requirements:
    pip install transformers torch tensorflow sentencepiece tf2onnx

Run once on desktop, then copy the outputs to App2/assets/models/:
    t5_encoder.tflite
    t5_decoder.tflite
    t5_vocab.txt

Usage:
    python tools/export_t5_tflite.py
"""

import os
import sys
import numpy as np

OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "App2", "assets", "models"
)

MODEL_ID = "prithivida/grammar_error_correcter_v1"  # T5-small, ~240 MB HuggingFace
MAX_LEN = 64


# ---------------------------------------------------------------------------
# 0. Sanity-check imports
# ---------------------------------------------------------------------------
try:
    import torch
    from transformers import AutoTokenizer, T5ForConditionalGeneration
    import tensorflow as tf
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with:  pip install transformers torch tensorflow sentencepiece")
    sys.exit(1)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"[1/5] Loading tokenizer and model: {MODEL_ID}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = T5ForConditionalGeneration.from_pretrained(MODEL_ID)
    model.eval()

    vocab_size = tokenizer.vocab_size
    hidden_size = model.config.d_model  # 512 for t5-small

    print(f"      vocab_size={vocab_size}  hidden_size={hidden_size}")

    # ---------------------------------------------------------------------------
    # 1. Export vocabulary (one token per line, index = id)
    # ---------------------------------------------------------------------------
    print("[2/5] Writing t5_vocab.txt")
    vocab_path = os.path.join(OUTPUT_DIR, "t5_vocab.txt")
    vocab = tokenizer.convert_ids_to_tokens(range(vocab_size))
    with open(vocab_path, "w", encoding="utf-8") as f:
        for tok in vocab:
            # Replace the SentencePiece prefix ▁ with a plain space prefix
            # so the Dart tokenizer can join on spaces naturally.
            f.write(tok.replace("▁", " ").strip() + "\n")
    print(f"      Wrote {len(vocab)} tokens → {vocab_path}")

    # ---------------------------------------------------------------------------
    # 2. Build TF encoder SavedModel wrapper
    # ---------------------------------------------------------------------------
    print("[3/5] Building TF encoder and exporting to TFLite")

    class EncoderWrapper(tf.Module):
        def __init__(self, pt_encoder):
            super().__init__()
            self._pt = pt_encoder

        @tf.function(
            input_signature=[
                tf.TensorSpec([1, MAX_LEN], tf.int32, name="input_ids"),
                tf.TensorSpec([1, MAX_LEN], tf.int32, name="attention_mask"),
            ]
        )
        def encode(self, input_ids, attention_mask):
            input_ids_pt = torch.tensor(input_ids.numpy(), dtype=torch.long)
            mask_pt = torch.tensor(attention_mask.numpy(), dtype=torch.long)
            with torch.no_grad():
                out = self._pt(input_ids=input_ids_pt, attention_mask=mask_pt)
            hidden = out.last_hidden_state.numpy()  # [1, seq, hidden]
            return tf.constant(hidden, dtype=tf.float32)

    # Use PyTorch model directly via tf.py_function for TFLite conversion
    # We instead use a direct torch→ONNX→TFLite route for reliability.

    print("      Using torch.onnx export path for encoder …")
    _export_encoder_tflite(model, tokenizer, hidden_size, OUTPUT_DIR)

    # ---------------------------------------------------------------------------
    # 3. Build TF decoder SavedModel wrapper
    # ---------------------------------------------------------------------------
    print("[4/5] Exporting decoder to TFLite")
    _export_decoder_tflite(model, tokenizer, vocab_size, hidden_size, OUTPUT_DIR)

    print("[5/5] Done.")
    print(f"  → {os.path.join(OUTPUT_DIR, 't5_encoder.tflite')}")
    print(f"  → {os.path.join(OUTPUT_DIR, 't5_decoder.tflite')}")
    print(f"  → {os.path.join(OUTPUT_DIR, 't5_vocab.txt')}")
    print()
    print("Copy these three files to App2/assets/models/ and rebuild the Flutter app.")


# ---------------------------------------------------------------------------
# Encoder export
# ---------------------------------------------------------------------------
def _export_encoder_tflite(model, tokenizer, hidden_size, out_dir):
    import torch

    dummy_ids = torch.zeros(1, MAX_LEN, dtype=torch.long)
    dummy_mask = torch.ones(1, MAX_LEN, dtype=torch.long)

    onnx_path = os.path.join(out_dir, "_t5_encoder.onnx")

    torch.onnx.export(
        model.encoder,
        (dummy_ids, dummy_mask),
        onnx_path,
        input_names=["input_ids", "attention_mask"],
        output_names=["hidden_states"],
        dynamic_axes={
            "input_ids": {0: "batch"},
            "attention_mask": {0: "batch"},
            "hidden_states": {0: "batch"},
        },
        opset_version=13,
    )

    _onnx_to_tflite(onnx_path, os.path.join(out_dir, "t5_encoder.tflite"))
    os.remove(onnx_path)


# ---------------------------------------------------------------------------
# Decoder export (single-step, greedy)
# ---------------------------------------------------------------------------
def _export_decoder_tflite(model, tokenizer, vocab_size, hidden_size, out_dir):
    import torch

    class DecoderStep(torch.nn.Module):
        """Single decoder step: takes decoder_input_ids [1,1] + encoder_hidden [1,seq,h]
        and returns logits [1,1,vocab_size]."""

        def __init__(self, decoder, lm_head):
            super().__init__()
            self.decoder = decoder
            self.lm_head = lm_head

        def forward(self, decoder_input_ids, encoder_hidden_states):
            out = self.decoder(
                input_ids=decoder_input_ids,
                encoder_hidden_states=encoder_hidden_states,
            )
            logits = self.lm_head(out.last_hidden_state)
            return logits

    step_model = DecoderStep(model.decoder, model.lm_head)
    step_model.eval()

    dummy_dec_ids = torch.zeros(1, 1, dtype=torch.long)
    dummy_enc_hidden = torch.zeros(1, MAX_LEN, hidden_size)

    onnx_path = os.path.join(out_dir, "_t5_decoder.onnx")

    torch.onnx.export(
        step_model,
        (dummy_dec_ids, dummy_enc_hidden),
        onnx_path,
        input_names=["decoder_input_ids", "encoder_hidden_states"],
        output_names=["logits"],
        dynamic_axes={
            "decoder_input_ids": {0: "batch"},
            "encoder_hidden_states": {0: "batch", 1: "seq"},
            "logits": {0: "batch"},
        },
        opset_version=13,
    )

    _onnx_to_tflite(onnx_path, os.path.join(out_dir, "t5_decoder.tflite"))
    os.remove(onnx_path)


# ---------------------------------------------------------------------------
# ONNX → TFLite via tf2onnx + TFLite converter
# ---------------------------------------------------------------------------
def _onnx_to_tflite(onnx_path: str, tflite_path: str):
    try:
        import onnx
        import tf2onnx
        import tensorflow as tf
    except ImportError:
        raise ImportError(
            "Install tf2onnx and onnx:  pip install tf2onnx onnx"
        )

    # Convert ONNX → TF SavedModel
    saved_model_dir = onnx_path.replace(".onnx", "_saved_model")
    os.system(
        f'python -m tf2onnx.convert --onnx "{onnx_path}" '
        f'--output "{saved_model_dir}" --target tensorflowjs'
    )

    # Alternatively, use onnx-tf
    try:
        import onnx
        from onnx_tf.backend import prepare

        onnx_model = onnx.load(onnx_path)
        tf_rep = prepare(onnx_model)
        tf_rep.export_graph(saved_model_dir)
    except ImportError:
        print("  onnx-tf not found, trying tf2onnx saved model route …")

    # Convert SavedModel → TFLite with float16 quantization
    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    with open(tflite_path, "wb") as f:
        f.write(tflite_model)

    # Clean up temp saved model
    import shutil
    if os.path.isdir(saved_model_dir):
        shutil.rmtree(saved_model_dir)

    size_mb = os.path.getsize(tflite_path) / 1024 / 1024
    print(f"      Wrote {tflite_path}  ({size_mb:.1f} MB)")


if __name__ == "__main__":
    main()
