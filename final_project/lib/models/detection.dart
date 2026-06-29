import 'package:flutter/foundation.dart';
// ייבוא ספריית foundation של Flutter - כולל כלים כמו @immutable ו-listEquals

/// מייצג אובייקט שזוהה בתמונה ע"י מערכת זיהוי המכשולים.
/// @immutable - המחלקה בלתי-ניתנת לשינוי לאחר יצירתה (כל השדות final)
@immutable
class Detection {
  /// סוג האובייקט שזוהה (למשל: אדם, רכב, אופניים).
  final String tag; // שדה קבוע - מוגדר פעם אחת בקונסטרקטור ולא משתנה

  /// רמת הביטחון של המודל בזיהוי (0.0 - 1.0).
  final double confidence; // ערך בין 0 ל-1, ככל שגבוה יותר - המודל יותר בטוח בזיהוי

  /// גבולות האובייקט בתמונה:
  /// [left, top, right, bottom]
  final List<double> box; // רשימה של 4 ערכים: left, top, right, bottom שמגדירים תיבה סביב האובייקט

  /// ציון הסיכון המחושב עבור האובייקט.
  final double riskScore; // ערך שמייצג כמה מסוכן האובייקט (למשל, רכב מתקרב = סיכון גבוה)

  /// מציין האם האובייקט נמצא בהתקרבות למשתמש.
  final bool isApproaching; // true = האובייקט מתקרב, false = מתרחק או עומד

  // קונסטרקטור של המחלקה - יוצר אובייקט Detection חדש עם named parameters
  Detection({
    required this.tag, // חובה לשלוח סוג אובייקט
    required this.confidence, // חובה לשלוח רמת ביטחון
    required List<double> box, // חובה לשלוח רשימת גבולות (מעובד לפני שמירה)
    this.riskScore = 0.0, // אופציונלי - ברירת מחדל 0.0 (אין סיכון)
    this.isApproaching = false, // אופציונלי - ברירת מחדל false (לא מתקרב)
  })  : assert(
  // בדיקת תקינות בזמן פיתוח (לא רץ ב-production)
  box.length == 4, // התנאי: אורך הרשימה חייב להיות 4
  'Box must contain [left, top, right, bottom]', // הודעת שגיאה אם התנאי נכשל
  ),
        box = List.unmodifiable(box); // יוצר עותק בלתי-ניתן לשינוי של הרשימה - שומר על immutability

  /// יוצר עותק של האובייקט עם אפשרות לעדכון שדות נבחרים.
  /// פונקציית copyWith היא דפוס נפוץ ב-Flutter - מאפשרת ליצור עותק חדש עם שינויים קלים
  Detection copyWith({
    // כל הפרמטרים אופציונליים (nullable)
    String? tag, // אם null - יישאר כמו המקור
    double? confidence, // אם null - יישאר כמו המקור
    List<double>? box, // אם null - יישאר כמו המקור
    double? riskScore, // אם null - יישאר כמו המקור
    bool? isApproaching, // אם null - יישאר כמו המקור
  }) {
    return Detection(
      // יוצר אובייקט Detection חדש
      tag: tag ?? this.tag, // ?? הוא null-aware operator: מחזיר את הערך הראשון שאינו null
      confidence: confidence ?? this.confidence, // אם נשלח ערך חדש - משתמש בו, אחרת - משתמש בערך הנוכחי
      box: box ?? this.box, // אותו היגיון
      riskScore: riskScore ?? this.riskScore, // אותו היגיון
      isApproaching: isApproaching ?? this.isApproaching, // אותו היגיון
    );
  }

  /// רוחב תיבת הזיהוי.
  double get width => (box[2] - box[0]).abs(); // getter - מחשב רוחב: right - left, עם abs() לערך חיובי

  /// גובה תיבת הזיהוי.
  double get height => (box[3] - box[1]).abs(); // מחשב גובה: bottom - top

  /// מיקום מרכז האובייקט בציר האופקי (X).
  double get centerX => (box[0] + box[2]) / 2; // ממוצע של שמאל וימין = מרכז אופקי

  /// מיקום מרכז האובייקט בציר האנכי (Y).
  double get centerY => (box[1] + box[3]) / 2; // ממוצע של למעלה ולמטה = מרכז אנכי

  /// שטח תיבת הזיהוי.
  double get area => width * height; // משתמש ב-getters שהגדרנו קודם (width ו-height)

  /// השוואה בין שני אובייקטים לפי תוכנם.
  /// דורס את אופרטור == (שוויון) - מאפשר להשוות שני אובייקטי Detection עם ==
  @override
  bool operator ==(Object other) =>
      // מקבל אובייקט כלשהו ומחזיר true/false
  identical(this, other) || // בדיקה מהירה: האם זה אותו אובייקט בזיכרון?
      other is Detection && // בדיקה שהאובייקט השני הוא גם מסוג Detection
          tag == other.tag && // משווה את סוג האובייקט
          confidence == other.confidence && // משווה את רמת הביטחון
          riskScore == other.riskScore && // משווה את ציון הסיכון
          isApproaching == other.isApproaching && // משווה את מצב ההתקרבות
          listEquals(box, other.box); // פונקציה מ-Flutter foundation להשוואת רשימות

  /// יצירת Hash Code עבור השוואות ואוספים.
  /// דורס את hashCode - חובה כשדורסים == - משמש לאוספים כמו Set ו-Map
  @override
  int get hashCode =>
      // מחזיר מספר שמייצג את האובייקט (hash)
  tag.hashCode ^ // XOR של hash של tag
  confidence.hashCode ^ // XOR של hash של confidence
  riskScore.hashCode ^ // XOR של hash של riskScore
  isApproaching.hashCode ^ // XOR של hash של isApproaching
  Object.hashAll(box); // פונקציה שיוצרת hash מרשימה שלמה, XOR (^) מערבב hash codes
}