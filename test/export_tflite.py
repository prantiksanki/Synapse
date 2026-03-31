from pathlib import Path
import sys


def main() -> int:
    model_path = Path(__file__).with_name("best.pt")
    if not model_path.exists():
        print(f"Model not found: {model_path}")
        return 1

    try:
        from ultralytics import YOLO
    except Exception as exc:
        print("Ultralytics is required to export the model.")
        print(f"Import error: {exc}")
        print("Recommended environment: Python 3.12 with ultralytics, tensorflow, tf_keras, onnxruntime, onnx2tf.")
        return 1

    try:
        import tensorflow as tf
        import tf_keras
    except Exception:
        tf = None
        tf_keras = None

    if tf is not None and tf_keras is not None:
        tf_version = ".".join(tf.__version__.split(".")[:2])
        keras_version = ".".join(tf_keras.__version__.split(".")[:2])
        if tf_version != keras_version:
            print("TensorFlow and tf_keras major/minor versions do not match.")
            print(f"tensorflow={tf.__version__}")
            print(f"tf_keras={tf_keras.__version__}")
            print("Use Python 3.12 and install matching versions, for example:")
            print("  py -3.12 -m pip install --user tensorflow==2.19.0 tf_keras==2.19.0 ultralytics onnxruntime onnx2tf onnx onnxslim onnx_graphsurgeon sng4onnx ai-edge-litert")
            print("Then run:")
            print("  py -3.12 export_tflite.py")
            return 1

    print(f"Loading {model_path.name}...")
    model = YOLO(str(model_path))

    print("Exporting to TensorFlow Lite...")
    output = model.export(format="tflite", imgsz=640)

    print("Export finished.")
    print(f"Output: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
