import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/formatters/metric_number_formatter.dart';

void main() {
  group('formatMetricNumber', () {
    test('omits decimal places for integer values', () {
      expect(formatMetricNumber(0), '0');
      expect(formatMetricNumber(70), '70');
      expect(formatMetricNumber(70.0), '70');
    });

    test('rounds non-integer values to one decimal place', () {
      expect(formatMetricNumber(70.24), '70.2');
      expect(formatMetricNumber(70.26), '70.3');
    });
  });
}
