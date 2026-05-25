/// Formats metric values without a decimal part when the value is an integer.
///
/// Non-integer values are rounded to one decimal place. This keeps kg/volume
/// labels concise while preserving the existing display behavior used across
/// workout, stats, and profile screens.
String formatMetricNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}
