enum StatsPeriodUnit {
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
    StatsPeriodUnit.daily => '일간',
    StatsPeriodUnit.weekly => '주간',
    StatsPeriodUnit.monthly => '월간',
  };

  String get metricPrefix => switch (this) {
    StatsPeriodUnit.daily => '일',
    StatsPeriodUnit.weekly => '주',
    StatsPeriodUnit.monthly => '월',
  };

  String get previousLabel => switch (this) {
    StatsPeriodUnit.daily => '전일',
    StatsPeriodUnit.weekly => '전주',
    StatsPeriodUnit.monthly => '전월',
  };

  String get emptyRangeLabel => switch (this) {
    StatsPeriodUnit.daily => '일별',
    StatsPeriodUnit.weekly => '주별',
    StatsPeriodUnit.monthly => '월별',
  };

  int get defaultRecentCount => switch (this) {
    StatsPeriodUnit.daily => 14,
    StatsPeriodUnit.weekly => 12,
    StatsPeriodUnit.monthly => 6,
  };
}
