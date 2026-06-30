import 'package:flutter/foundation.dart';

/// מייצג אובייקט שזוהה על ידי מודל הזיהוי.
@immutable
class Detection {
  /// סוג האובייקט שזוהה.
  final String tag;

  /// רמת הביטחון של המודל בזיהוי.
  final double confidence;

  /// גבולות תיבת הזיהוי: [left, top, right, bottom].
  final List<double> box;

  /// ציון הסיכון המחושב עבור האובייקט.
  final double riskScore;

  /// מציין האם האובייקט מתקרב למשתמש.
  final bool isApproaching;

  Detection({
    required this.tag,
    required this.confidence,
    required List<double> box,
    this.riskScore = 0.0,
    this.isApproaching = false,
  })  : assert(
  box.length == 4,
  'Box must contain [left, top, right, bottom]',
  ),
        box = List.unmodifiable(box);

  /// יוצר עותק חדש עם אפשרות לעדכון חלק מהשדות.
  Detection copyWith({
    String? tag,
    double? confidence,
    List<double>? box,
    double? riskScore,
    bool? isApproaching,
  }) {
    return Detection(
      tag: tag ?? this.tag,
      confidence: confidence ?? this.confidence,
      box: box ?? this.box,
      riskScore: riskScore ?? this.riskScore,
      isApproaching: isApproaching ?? this.isApproaching,
    );
  }

  /// רוחב תיבת הזיהוי.
  double get width => (box[2] - box[0]).abs();

  /// גובה תיבת הזיהוי.
  double get height => (box[3] - box[1]).abs();

  /// מרכז האובייקט בציר X.
  double get centerX => (box[0] + box[2]) / 2;

  /// מרכז האובייקט בציר Y.
  double get centerY => (box[1] + box[3]) / 2;

  /// שטח תיבת הזיהוי.
  double get area => width * height;

  /// משווה בין שני זיהויים לפי תוכן השדות.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Detection &&
              tag == other.tag &&
              confidence == other.confidence &&
              riskScore == other.riskScore &&
              isApproaching == other.isApproaching &&
              listEquals(box, other.box);

  /// מייצר hashCode עקבי בהתאם לשדות המחלקה.
  @override
  int get hashCode =>
      tag.hashCode ^
      confidence.hashCode ^
      riskScore.hashCode ^
      isApproaching.hashCode ^
      Object.hashAll(box);
}