from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterable

import numpy as np
import tensorflow as tf


@dataclass(frozen=True)
class TFLiteExportResult:
    tflite_bytes: bytes
    input_dtype: str
    output_dtype: str


def export_quantized_tflite(
    keras_model: tf.keras.Model,
    representative_samples: np.ndarray,
    out_path: str,
    int8: bool = True,
) -> TFLiteExportResult:
    """
    Export a Keras model to a quantized TFLite model.

    - Uses post-training quantization with a representative dataset.
    - For on-device speed, int8 is preferred if your inference stack supports it.
    """
    converter = tf.lite.TFLiteConverter.from_keras_model(keras_model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    rep = representative_samples.astype(np.float32)

    def rep_gen():
        for i in range(min(len(rep), 512)):
            yield [rep[i : i + 1]]

    converter.representative_dataset = rep_gen

    if int8:
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.int8
        converter.inference_output_type = tf.int8

    tflite_model = converter.convert()
    with open(out_path, "wb") as f:
        f.write(tflite_model)

    # Extract basic dtype info by inspecting interpreter tensors.
    interp = tf.lite.Interpreter(model_content=tflite_model)
    interp.allocate_tensors()
    in_dtype = str(interp.get_input_details()[0]["dtype"])
    out_dtype = str(interp.get_output_details()[0]["dtype"])

    return TFLiteExportResult(tflite_bytes=tflite_model, input_dtype=in_dtype, output_dtype=out_dtype)

