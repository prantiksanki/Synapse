from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    here = Path(__file__).resolve().parent
    root = here.parent

    parser = argparse.ArgumentParser(
        description="Convert Keras .h5 sign model to TensorFlow.js format for WASM runtime."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=root / "model.h5",
        help="Path to source Keras .h5 model.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=here / "web" / "tfjs_model",
        help="Output directory for TensorFlow.js model files.",
    )
    parser.add_argument(
        "--labels",
        type=Path,
        default=root / "labels.txt",
        help="Path to labels.txt used by training/inference.",
    )
    parser.add_argument(
        "--norm",
        type=Path,
        default=root / "normalization.json",
        help="Path to normalization.json used by training/inference.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        import tensorflow as tf
        import tensorflowjs as tfjs
    except ImportError as exc:
        raise RuntimeError(
            "Missing dependency. Install with:\n"
            "python -m pip install tensorflow tensorflowjs"
        ) from exc

    input_model = args.input.resolve()
    output_dir = args.output.resolve()
    labels_path = args.labels.resolve()
    norm_path = args.norm.resolve()

    if not input_model.exists():
        raise FileNotFoundError(f"Model not found: {input_model}")
    if not labels_path.exists():
        raise FileNotFoundError(f"Labels file not found: {labels_path}")
    if not norm_path.exists():
        raise FileNotFoundError(f"Normalization file not found: {norm_path}")

    output_dir.mkdir(parents=True, exist_ok=True)

    model = tf.keras.models.load_model(str(input_model), compile=False)
    tfjs.converters.save_keras_model(model, str(output_dir))

    # Keep preprocessing metadata next to the web model.
    shutil.copy2(labels_path, output_dir / "labels.txt")
    shutil.copy2(norm_path, output_dir / "normalization.json")

    input_shape = [int(v) if v is not None else None for v in model.input_shape]
    output_shape = [int(v) if v is not None else None for v in model.output_shape]

    metadata = {
        "source_model": str(input_model),
        "format": "tfjs_layers_model",
        "runtime": "tfjs_wasm",
        "input_shape": input_shape,
        "output_shape": output_shape,
    }
    (output_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2),
        encoding="utf-8",
    )

    print("Conversion complete")
    print(f"Model JSON: {output_dir / 'model.json'}")
    print(f"Weights  : {output_dir / 'group1-shard1of1.bin'}")
    print(f"Labels   : {output_dir / 'labels.txt'}")
    print(f"Norm     : {output_dir / 'normalization.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

