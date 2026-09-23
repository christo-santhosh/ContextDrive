import numpy as np
import tensorflow as tf

interpreter = tf.lite.Interpreter(model_path="assets/detect.tflite")
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()[0]
input_shape = input_details['shape']
input_data = np.zeros(input_shape, dtype=np.uint8)

interpreter.set_tensor(input_details['index'], input_data)
interpreter.invoke()

print("\nOutputs after inference:")
for i, tensor in enumerate(interpreter.get_output_details()):
    data = interpreter.get_tensor(tensor['index'])
    print(f"Index {i}: name={tensor['name']}, shape={data.shape}")
