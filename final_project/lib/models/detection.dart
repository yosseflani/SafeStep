import 'package:flutter/foundation.dart';
// ייבוא כלים בסיסיים כמו @immutable ו-listEquals

@immutable
class Detection {
  // מחלקה שמייצגת אובייקט שזוהה (Immutable = לא משתנה אחרי יצירה)

  final String tag;
  // שם האובייקט (למשל: car, person)

  final double confidence;
  // רמת ביטחון של המודל (בין 0 ל-1)

  final List<double> box;
  // מיקום האובייקט: [left, top, right, bottom]

  final double riskScore;
  // ציון סיכון (מחושב בנפרד)

  final bool isApproaching;
  // האם האובייקט מתקרב למשתמש

  Detection({
    required this.tag,
    required this.confidence,
    required List<double> box,
    this.riskScore = 0.0,
    // אם לא נשלח ערך → ברירת מחדל 0
    this.isApproaching = false,
    // אם לא נשלח ערך → ברירת מחדל false
  })  : assert(box.length == 4, 'Box must have exactly 4 values: [left, top, right, bottom]'),
  // בודק שהרשימה באורך 4
        box = List.unmodifiable(box);
  // הופך את הרשימה ללא ניתנת לשינוי (Immutable)

  // יוצר עותק של האובייקט עם שינויים
  Detection copyWith({
    String? tag,
    double? confidence,
    List<double>? box,
    double? riskScore,
    bool? isApproaching,
  }) {
    return Detection(
      tag: tag ?? this.tag,
      // אם לא נשלח tag → נשאר הישן

      confidence: confidence ?? this.confidence,
      // אותו דבר ל-confidence

      box: box ?? this.box,
      // אם לא נשלח box → נשאר אותו דבר

      riskScore: riskScore ?? this.riskScore,
      // עדכון riskScore אם רוצים

      isApproaching: isApproaching ?? this.isApproaching,
      // עדכון מצב התקרבות אם רוצים
    );
  }

  // חישובים גיאומטריים מה-box

  double get width => (box[2] - box[0]).abs();
  // רוחב = right - left

  double get height => (box[3] - box[1]).abs();
  // גובה = bottom - top

  double get centerX => (box[0] + box[2]) / 2;
  // מרכז X

  double get centerY => (box[1] + box[3]) / 2;
  // מרכז Y

  double get area => width * height;
  // שטח האובייקט

  // השוואה בין שני אובייקטים
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          // אם זה אותו אובייקט בזיכרון
          other is Detection &&
              // בודק שזה אותו סוג
              tag == other.tag &&
              confidence == other.confidence &&
              riskScore == other.riskScore &&
              isApproaching == other.isApproaching &&
              listEquals(box, other.box);
  // משווה גם את הרשימה (List)

  @override
  int get hashCode =>
      tag.hashCode ^
      confidence.hashCode ^
      riskScore.hashCode ^
      isApproaching.hashCode ^
      Object.hashAll(box);
// יוצר מזהה ייחודי לאובייקט
}