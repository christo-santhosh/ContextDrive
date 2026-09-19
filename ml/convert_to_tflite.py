import tensorflow as tf
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SAVED_MODEL_DIR = os.path.join(SCRIPT_DIR, "models/ssd_mobilenet_v2_fpnlite_320x320_coco17_tpu-8/saved_model")
ASSETS_DIR = os.path.join(SCRIPT_DIR, "../app/assets")
TFLITE_MODEL_PATH = os.path.join(ASSETS_DIR, "detect.tflite")

print(f"Loading SavedModel from: {SAVED_MODEL_DIR}")
converter = tf.lite.TFLiteConverter.from_saved_model(SAVED_MODEL_DIR)

# Removed quantization to keep output tensors as Float32
# converter.optimizations = [tf.lite.Optimize.DEFAULT]
# Ensure we include TF ops if needed by the model
converter.target_spec.supported_ops = [
    tf.lite.OpsSet.TFLITE_BUILTINS, # enable TensorFlow Lite ops.
    tf.lite.OpsSet.SELECT_TF_OPS # enable TensorFlow ops.
]

print("Converting model to TFLite (this may take a minute)...")
tflite_model = converter.convert()

if not os.path.exists(ASSETS_DIR):
    os.makedirs(ASSETS_DIR)

with open(TFLITE_MODEL_PATH, 'wb') as f:
    f.write(tflite_model)
    
print(f"Successfully exported TFLite model to {TFLITE_MODEL_PATH}")
