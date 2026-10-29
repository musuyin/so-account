import '../../../core/time/business_date.dart';

enum ReportPeriod { week, month, year, custom }

class ReportRange {
  const ReportRange(this.start, this.end, this.period);
  final DateTime start, end;
  final ReportPeriod period;
  factory ReportRange.at(
    ReportPeriod period,
    DateTime anchor, {
    DateTime? customStart,
    DateTime? customEnd,
  }) => switch (period) {
    ReportPeriod.week => ReportRange(
      DateTime(anchor.year, anchor.month, anchor.day - 6),
      DateTime(anchor.year, anchor.month, anchor.day + 1),
      period,
    ),
    ReportPeriod.month => ReportRange(
      DateTime(anchor.year, anchor.month),
      DateTime(anchor.year, anchor.month + 1),
      period,
    ),
    ReportPeriod.year => ReportRange(
      DateTime(anchor.year),
      DateTime(anchor.year + 1),
      period,
    ),
    ReportPeriod.custom => ReportRange(
      customStart ?? DateTime(anchor.year, anchor.month),
      DateTime(
        (customEnd ?? anchor).year,
        (customEnd ?? anchor).month,
        (customEnd ?? anchor).day + 1,
      ),
      period,
    ),
  };
  int get days => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
  ReportRange get previous => switch (period) {
    ReportPeriod.month => ReportRange(
      DateTime(start.year, start.month - 1),
      start,
      period,
    ),
    ReportPeriod.year => ReportRange(DateTime(start.year - 1), start, period),
    _ => ReportRange(
      DateTime(start.year, start.month, start.day - days),
      start,
      period,
    ),
  };
  List<String> get buckets {
    final result = <String>[];
    for (
      var date = start;
      date.isBefore(end);
      date = monthlyBuckets
          ? DateTime(date.year, date.month + 1)
          : DateTime(date.year, date.month, date.day + (weeklyBuckets ? 7 : 1))
    ) {
      result.add(monthlyBuckets ? monthKey(date) : dateKey(date));
    }
    return result;
  }

  bool get monthlyBuckets =>
      period == ReportPeriod.year ||
      (period == ReportPeriod.custom && days > 90);
  bool get weeklyBuckets =>
      period == ReportPeriod.custom && days > 31 && days <= 90;
  (DateTime, DateTime) intervalFor(String label) {
    var from = parseDate(label.length == 7 ? '$label-01' : label);
    var until = monthlyBuckets
        ? DateTime(from.year, from.month + 1)
        : DateTime(from.year, from.month, from.day + (weeklyBuckets ? 7 : 1));
    if (from.isBefore(start)) from = start;
    if (until.isAfter(end)) until = end;
    return (from, until);
  }
}
