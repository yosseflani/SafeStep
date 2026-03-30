import 'package:flutter/foundation.dart';

@immutable
class Detection { // מחלקה שייצגת זיהוי אחד
  final String tag; // שם
  final double confidence; // כמה המודל בטוח בזיהוי
  final List<double> box; // [left, top, right, bottom, conf?] מיקום במסך
  final double riskScore; // ציון הסיכון

  // יוצר אובייקט detection
  const Detection({
    required this.tag,
    required this.confidence,
    required this.box,
    this.riskScore = 0.0, // בשלב הראשון המודל מחזיר זיהוי בלי risk score אז מאתחלים לאפס
  });

  // בגלל ש detection לא ניתן לשינוי יוצרים את האובייקט הזה כדי לעדכן את risk score - יוצרת עותק חדש עם הערכים המעודכנים
  // בגלל שהזיהוי רץ בכמה קבצים יותר בטיחותי לעשות ככה
  // בפועל - נוצר אובייקט חדש, אבל משתמשים רק בחדש במקום בישן אז זה כמו החלפה
  Detection copyWith({
    String? tag,
    double? confidence,
    List<double>? box,
    double? riskScore,
  }) {
    return Detection(
      tag: tag ?? this.tag,
      confidence: confidence ?? this.confidence,
      box: box ?? this.box,
      riskScore: riskScore ?? this.riskScore,
    );
  }


// 0 שמאלה, 1 למעלה, 2 ימינה, 3 למטה, 4 רמת ביטחון בזיהוי
  double get width => (box[2] - box[0]).abs();
  double get height => (box[3] - box[1]).abs();
  double get centerX => (box[0] + box[2]) / 2;
  double get centerY => (box[1] + box[3]) / 2;
  double get area => width * height;
}