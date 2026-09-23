import tensorflow as tf

interpreter = tf.lite.Interpreter(model_path="assets/detect.tflite")
interpreter.allocate_tensors()

print("Inputs:")
for tensor in interpreter.get_input_details():
    print(tensor)

print("\nOutputs:")
for tensor in interpreter.get_output_details():
    print(tensor)
