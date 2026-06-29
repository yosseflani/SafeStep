import 'dart:math'; // ייבוא ספריית math של Dart - מספקת פונקציות כמו log(), ln10, min(), max()

import 'package:flutter/foundation.dart'; // ייבוא ספריית foundation של Flutter - כולל kDebugMode, debugPrint

import '../models/detection.dart'; // ייבוא המחלקה Detection שמייצגת אובייקט מזוהה

/// שירות לחישוב ציון סיכון עבור כל אובייקט שזוהה בתמונה.
///
/// הציון מבוסס על:
/// 1. סוג האובייקט
/// 2. מיקום בתמונה
/// 3. גודל יחסי
/// 4. רמת ביטחון של המודל
/// 5. שינוי בגודל בין פריימים
/// 6. תנועה אנכית בתמונה
class RiskScoringService {
  double _imageWidth = 640; // רוחב ברירת מחדל של התמונה (פיקסלים)
  double _imageHeight = 480; // גובה ברירת מחדל של התמונה (פיקסלים)

  /// היסטוריה של אובייקטים מפריימים קודמים.
  final Map<String, _ObjectHistory> _history = {}; // Map שמאחסן היסטוריה של כל אובייקט לפי מפתח ייחודי
  // המפתח הוא שילוב של tag + מיקום משוער (grid)

  DateTime _lastCleanup = DateTime.now(); // זמן הניקוי האחרון של היסטוריה ישנה

  /// כל כמה זמן מנקים אובייקטים ישנים מההיסטוריה.
  static const _cleanupInterval = Duration(seconds: 30); // כל 30 שניות מנקים אובייקטים שלא נראו

  /// גודל תא למעקב מקורב אחרי אותו אובייקט בין פריימים.
  static const double _gridSize = 60.0; // גודל תא של 60 פיקסלים - משמש ליצירת מפתח ייחודי לאובייקט

  /// משקלים לחישוב הסיכון הסופי.
  ///
  /// התקרבות ומהירות קיבלו משקל משמעותי,
  /// כי באפליקציה בזמן אמת אובייקט שמתקרב הוא מסוכן יותר.
  static const _weights = _RiskWeights( // אובייקט קבוע שמגדיר את המשקלים של כל גורם
    objectType: 0.30, // 30% - סוג האובייקט (רכב = מסוכן יותר מספסל)
    position: 0.22, // 22% - מיקום בתמונה (מרכז = מסוכן יותר)
    size: 0.14, // 14% - גודל יחסי (גדול = קרוב = מסוכן)
    confidence: 0.10, // 10% - רמת ביטחון של המודל
    changeRate: 0.14, // 14% - קצב שינוי בגודל (גדל = מתקרב)
    velocity: 0.10, // 10% - מהירות תנועה אנכית (יורד = מתקרב)
  );
  // סך הכל: 0.30 + 0.22 + 0.14 + 0.10 + 0.14 + 0.10 = 1.0 (100%)

  /// ספים לסינון זיהויים חלשים ולזיהוי אובייקט מתקרב.
  static const _thresholds = _RiskThresholds( // אובייקט קבוע שמגדיר ספים
    approachingChangeRate: 8.0, // אם האובייקט גדל ביותר מ-8% בפריים - נחשב מתקרב
    approachingVelocity: 6.0, // אם האובייקט זז למטה ביותר מ-6% מגובה התמונה - נחשב מתקרב
    minConfidence: 0.30, // ביטחון מינימלי של 30% כדי לכלול זיהוי בחישוב
  );

  /// מעדכן את רזולוציית התמונה.
  ///
  /// חשוב לקרוא לזה כאשר גודל התמונה מהמצלמה משתנה.
  void updateResolution(int width, int height) { // מקבל רוחב וגובה חדשים
    if (width <= 0 || height <= 0) return; // בדיקת תקינות - אם לא חוקי, יציאה

    _imageWidth = width.toDouble(); // עדכון רוחב התמונה (המרה ל-double)
    _imageHeight = height.toDouble(); // עדכון גובה התמונה (המרה ל-double)
  }

  /// מקבל רשימת זיהויים, מסנן זיהויים חלשים,
  /// מחשב ציון סיכון ומחזיר רשימה ממוינת מהמסוכן ביותר לפחות מסוכן.
  List<Detection> scoreDetections(List<Detection> detections) { // מקבל רשימת זיהויים גולמית
    _maybeCleanup(); // ניקוי אובייקטים ישנים מההיסטוריה (אם הגיע הזמן)

    final filtered = detections // סינון זיהויים עם ביטחון נמוך
        .where((d) => d.confidence >= _thresholds.minConfidence) // שומר רק זיהויים עם ביטחון >= 30%
        .toList(); // המרה חזרה לרשימה

    final scored = filtered.map(_scoreSingleDetection).toList(); // חישוב ציון סיכון לכל זיהוי
    // map() - מפעיל את _scoreSingleDetection על כל איבר ברשימה

    scored.sort((a, b) => b.riskScore.compareTo(a.riskScore)); // מיון מהציון הגבוה למסוכן ביותר
    // sort() - מסדר את הרשימה לפי ציון סיכון (יורד)
    // b.compareTo(a) - סדר יורד (הגבוה ביותר ראשון)

    return scored; // החזרת הרשימה הממוינת
  }

  /// איפוס ההיסטוריה.
  ///
  /// שימושי בעת החלפת מצלמה, מעבר מסך או התחלת זיהוי מחדש.
  void reset() {
    _history.clear(); // מחיקת כל ההיסטוריה
    _lastCleanup = DateTime.now(); // עדכון זמן הניקוי האחרון
  }

  /// מחשב ציון סיכון עבור זיהוי יחיד.
  Detection _scoreSingleDetection(Detection detection) { // פונקציה פרטית שמקבלת זיהוי אחד
    try { // בלוק try-catch לטיפול בשגיאות
      final objectType = _getObjectTypeWeight(detection.tag); // חישוב ציון לפי סוג האובייקט
      final position = _calculatePositionFactor(detection); // חישוב ציון לפי מיקום
      final size = _calculateSizeFactor(detection); // חישוב ציון לפי גודל
      final confidence = _calculateConfidenceFactor(detection); // חישוב ציון לפי ביטחון
      final changeRate = _calculateChangeRateFactor(detection); // חישוב קצב שינוי בגודל
      final velocity = _calculateVelocityFactor(detection); // חישוב מהירות תנועה אנכית

      final rawRisk = // חישוב ציון סיכון גולמי (לפני החלקה)
      (objectType * _weights.objectType) + // סוג * משקל
          (position * _weights.position) + // מיקום * משקל
          (size * _weights.size) + // גודל * משקל
          (confidence * _weights.confidence) + // ביטחון * משקל
          (changeRate * _weights.changeRate) + // קצב שינוי * משקל
          (velocity * _weights.velocity); // מהירות * משקל
      // סכום משוקלל של כל הגורמים

      final isApproaching = // בדיקה אם האובייקט מתקרב
      changeRate >= _thresholds.approachingChangeRate || // אם גדל ביותר מ-8%
          velocity >= _thresholds.approachingVelocity; // או זז למטה ביותר מ-6%

      final key = _getInstanceKey(detection); // יצירת מפתח ייחודי לאובייקט
      final previousScore = _history[key]?.previousScore ?? rawRisk; // קבלת ציון קודם (אם קיים)
      // ? = null-aware operator - אם _history[key] null, אז ?.previousScore null
      // ?? = אם null, משתמש ב-rawRisk

      /// אם האובייקט מתקרב, מגיבים מהר יותר לשינוי בציון.
      /// אם הוא לא מתקרב, מחליקים יותר כדי למנוע קפיצות.
      final smoothed = _smoothScore( // החלקת הציון למניעת קפיצות חדות
        rawRisk, // ציון נוכחי
        previousScore, // ציון קודם
        alpha: isApproaching ? 0.70 : 0.45, // מקדם החלקה - גבוה יותר = תגובה מהירה יותר
        // אם מתקרב: alpha=0.70 (70% מהציון החדש, 30% מהישן) - תגובה מהירה
        // אם לא מתקרב: alpha=0.45 (45% מהחדש, 55% מהישן) - החלקה חזקה יותר
      ).clamp(0.0, 100.0); // הגבלת הציון בין 0 ל-100

      _history[key] = _ObjectHistory( // שמירת היסטוריה של האובייקט
        area: detection.area, // שטח נוכחי
        centerX: detection.centerX, // מיקום מרכז X
        centerY: detection.centerY, // מיקום מרכז Y
        previousScore: smoothed, // ציון מוחלק (ישמש בפריים הבא)
        lastSeen: DateTime.now(), // זמן אחרון שנראה
      );

      return detection.copyWith( // יצירת עותק חדש של Detection עם ציון סיכון מעודכן
        riskScore: smoothed, // ציון סיכון מוחלק
        isApproaching: isApproaching, // האם מתקרב
      );
    } catch (e, stack) { // תפיסת שגיאות
      _debug('score error for ${detection.tag}: $e\n$stack'); // הדפסת שגיאה

      return detection.copyWith( // במקרה של שגיאה - החזרת ציון ברירת מחדל
        riskScore: 30.0, // ציון נמוך (לא מסוכן)
        isApproaching: false, // לא מתקרב
      );
    }
  }

  /// מחזיר ציון בסיסי לפי סוג האובייקט.
  ///
  /// רכב ואופנוע הם הכי מסוכנים.
  /// עמוד הוא מכשול קשיח ולכן מסוכן מאוד.
  /// מעבר חציה הוא מידע ניווטי, לא מכשול, ולכן מקבל ציון נמוך יחסית.
  double _getObjectTypeWeight(String tag) => switch (tag) { // switch expression - תחביר חדש ב-Dart
    'car' || 'motorcycle' => 100.0, // רכב או אופנוע = הכי מסוכן (100)
    'pole' => 88.0, // עמוד = מסוכן מאוד (88) - מכשול קשיח
    'person' => 78.0, // אדם = מסוכן (78)
    'bench' || 'couch' => 55.0, // ספסל או ספה = בינוני (55)
    'crosswalk' => 35.0, // מעבר חצייה = נמוך (35) - מידע ניווטי, לא מכשול
    _ => 15.0, // ברירת מחדל = נמוך מאוד (15) - _ = wildcard (כל דבר אחר)
  };

  /// מחשב סיכון לפי מיקום האובייקט בתמונה.
  ///
  /// אובייקט במרכז מסוכן יותר מאובייקט בצד.
  /// אובייקט בתחתית התמונה נחשב קרוב יותר למשתמש.
  double _calculatePositionFactor(Detection d) { // מקבל Detection ומחזיר ציון 0-100
    if (_imageWidth <= 0 || _imageHeight <= 0) return 30.0; // אם רזולוציה לא תקינה - ציון ברירת מחדל

    final normX = (d.centerX / _imageWidth).clamp(0.0, 1.0); // נרמול X ל-0 עד 1 (0=שמאל, 1=ימין)
    final normY = (d.centerY / _imageHeight).clamp(0.0, 1.0); // נרמול Y ל-0 עד 1 (0=למעלה, 1=למטה)

    final xFactor = (1.0 - (normX - 0.5).abs() * 2.0).clamp(0.0, 1.0); // ציון מיקום אופקי
    // normX - 0.5 = מרחק מהמרכז (0.5)
    // .abs() = ערך מוחלט (לא משמש איזה צד)
    // * 2.0 = הכפלה (הופך את הטווח ל-0 עד 1)
    // 1.0 - ... = היפוך (מרכז = 1, צד = 0)
    // clamp = הגבלה ל-0 עד 1

    final yFactor = normY; // ציון מיקום אנכי - פשוט normY (למטה = גבוה)
    // ככל ש-normY גבוה יותר (קרוב ל-1) = האובייקט בתחתית = קרוב יותר

    return ((xFactor * 0.40 + yFactor * 0.60) * 100).clamp(0.0, 100.0); // ציון סופי
    // 40% מיקום אופקי + 60% מיקום אנכי (אנכי חשוב יותר)
    // * 100 = המרה ל-0 עד 100
  }

  /// מחשב סיכון לפי גודל האובייקט ביחס לתמונה.
  ///
  /// משתמשים בסקאלה לוגריתמית כדי שגם אובייקטים שתופסים אחוזים בודדים
  /// מהתמונה יקבלו משמעות סבירה ולא ציון נמוך מדי.
  double _calculateSizeFactor(Detection d) { // מקבל Detection ומחזיר ציון 0-100
    final imageArea = _imageWidth * _imageHeight; // שטח התמונה הכולל (פיקסלים)

    if (imageArea <= 0) return 30.0; // אם שטח לא תקין - ציון ברירת מחדל

    final ratio = (d.area / imageArea).clamp(1e-6, 1.0); // יחס שטח האובייקט לשטח התמונה
    // d.area = שטח האובייקט (רוחב * גובה)
    // clamp(1e-6, 1.0) = הגבלה בין 0.000001 ל-1 (מונע log(0) שנותן שגיאה)

    final logRatio = log(ratio) / ln10; // לוגריתם בסיס 10 של היחס
    // log() = לוגריתם טבעי (בסיס e)
    // ln10 = לוגריתם טבעי של 10
    // log(ratio) / ln10 = log10(ratio) - לוגריתם בסיס 10
    // לוגריתם מקטין את הטווח: אובייקט קטן מאוד לא יקבל ציון נמוך מדי

    return (((logRatio + 6.0) / 6.0).clamp(0.0, 1.0) * 100); // ציון סופי
    // logRatio + 6.0 = הזזה (לוגריתם שלילי הופך לחיובי)
    // / 6.0 = נרמול ל-0 עד 1
    // clamp = הגבלה ל-0 עד 1
    // * 100 = המרה ל-0 עד 100
  }

  /// ממיר confidence של המודל לציון בין 0 ל-100.
  double _calculateConfidenceFactor(Detection d) { // מקבל Detection ומחזיר ציון 0-100
    return (d.confidence * 100).clamp(0.0, 100.0); // המרה מ-0-1 ל-0-100
    // d.confidence = ערך בין 0 ל-1
    // * 100 = המרה ל-0 עד 100
  }

  /// מחשב האם האובייקט גדל ביחס לפריים הקודם.
  ///
  /// גידול בשטח יכול להעיד שהאובייקט מתקרב למצלמה.
  double _calculateChangeRateFactor(Detection d) { // מקבל Detection ומחזיר אחוז גידול
    final previous = _history[_getInstanceKey(d)]; // קבלת היסטוריה קודמת של האובייקט

    if (previous == null || previous.area <= 0) return 0.0; // אם אין היסטוריה - החזר 0

    final ratio = (d.area - previous.area) / previous.area; // חישוב אחוז שינוי
    // (שטח נוכחי - שטח קודם) / שטח קודם = אחוז שינוי
    // אם גדל: ratio > 0, אם קטן: ratio < 0

    return ratio > 0 ? (ratio * 100).clamp(0.0, 100.0) : 0.0; // החזרת אחוז גידול (חיובי בלבד)
    // אם ratio > 0 (גדל) - החזר ratio * 100 (אחוז)
    // אם ratio <= 0 (קטן או ללא שינוי) - החזר 0
  }

  /// מחשב תנועה כלפי מטה בתמונה.
  ///
  /// בהרבה מצבי מצלמה, אובייקט שנע כלפי תחתית התמונה מתקרב למשתמש.
  double _calculateVelocityFactor(Detection d) { // מקבל Detection ומחזיר ציון תנועה
    final previous = _history[_getInstanceKey(d)]; // קבלת היסטוריה קודמת

    if (previous == null || _imageHeight <= 0) return 0.0; // אם אין היסטוריה - החזר 0

    final normalized = (d.centerY - previous.centerY) / _imageHeight; // תנועה אנכית מנורמלת
    // centerY נוכחי - centerY קודם = כמה זז למטה (חיובי) או למעלה (שלילי)
    // / _imageHeight = נרמול ל-0 עד 1 (או -1 עד 0)

    return normalized > 0 ? (normalized * 100).clamp(0.0, 100.0) : 0.0; // החזרת ציון תנועה למטה
    // אם normalized > 0 (זז למטה) - החזר normalized * 100
    // אם normalized <= 0 (זז למעלה או ללא תנועה) - החזר 0
  }

  /// יוצר מפתח מקורב למעקב אחר אותו אובייקט בין פריימים.
  ///
  /// זה לא tracking מושלם, אבל מספיק טוב למעקב בסיסי ומהיר.
  String _getInstanceKey(Detection d) { // יוצר מחרוזת ייחודית לאובייקט
    return '${d.tag}_${d.centerX ~/ _gridSize}_${d.centerY ~/ _gridSize}'; // מפתח = tag_X_Y
    // ~/ = חילוק שלם (integer division) - מחלק ומעגל למטה
    // דוגמה: אם centerX=150, _gridSize=60, אז 150~/60 = 2
    // זה יוצר "רשת" (grid) של תאים בגודל 60x60 פיקסלים
    // אובייקטים באותו תא יקבלו אותו מפתח (מעקב מקורב)
  }

  /// החלקת ציון סיכון כדי למנוע קפיצות חדות בין פריימים.
  double _smoothScore( // פונקציית החלקה (exponential smoothing)
      double current, // ציון נוכחי
      double previous, // ציון קודם
          {
        double alpha = 0.5, // מקדם החלקה (0 עד 1) - ברירת מחדל 0.5
      }) {
    return alpha * current + (1.0 - alpha) * previous; // נוסחת החלקה מעריכית
    // alpha * current = חלק מהציון החדש
    // (1.0 - alpha) * previous = חלק מהציון הישן
    // אם alpha=0.70: 70% מהחדש + 30% מהישן = תגובה מהירה
    // אם alpha=0.45: 45% מהחדש + 55% מהישן = החלקה חזקה
  }

  /// מנקה מההיסטוריה אובייקטים שלא נראו לאחרונה.
  void _maybeCleanup() { // בדיקה אם הגיע הזמן לניקוי
    final now = DateTime.now(); // זמן נוכחי

    if (now.difference(_lastCleanup) < _cleanupInterval) return; // אם לא עברו 30 שניות - יציאה
    // difference() = הפרש זמנים
    // < _cleanupInterval = אם קטן מ-30 שניות

    final cutoff = now.subtract(const Duration(seconds: 30)); // זמן cutoff - אובייקטים לפני זה יימחקו

    _history.removeWhere((_, h) => h.lastSeen.isBefore(cutoff)); // מחיקת אובייקטים ישנים
    // removeWhere() = מחיקת איברים שעומדים בתנאי
    // (_, h) = _ = מפתח (לא בשימוש), h = ערך (_ObjectHistory)
    // h.lastSeen.isBefore(cutoff) = אם lastSeen לפני cutoff - מחק

    _lastCleanup = now; // עדכון זמן הניקוי האחרון
  }

  /// הדפסת הודעות Debug רק בזמן פיתוח.
  void _debug(String msg) { // פונקציה פרטית להדפסת debug
    if (!kDebugMode) return; // אם לא במצב debug - יציאה

    final time = DateTime.now() // קבלת הזמן הנוכחי
        .toIso8601String() // המרה לפורמט ISO 8601
        .split('T') // פיצול לפי T
        .last // לקיחת השעה
        .split('.') // פיצול לפי נקודה
        .first; // לקיחת שעה ללא מילישניות

    debugPrint('[RiskScoring][$time] $msg'); // הדפסה בפורמט: [שם השירות][שעה] הודעה
  }
}

/// משקלים של כל גורם בציון הסיכון הסופי.
///
/// חשוב שסכום המשקלים יהיה 1.0.
class _RiskWeights { // מחלקה פרטית (מתחיל ב-_) - לא נגישה מחוץ לקובץ זה
  final double objectType; // משקל סוג האובייקט
  final double position; // משקל מיקום
  final double size; // משקל גודל
  final double confidence; // משקל ביטחון
  final double changeRate; // משקל קצב שינוי
  final double velocity; // משקל מהירות

  const _RiskWeights({ // קונסטרקטור קבוע (const) - אופטימיזציה
    required this.objectType, // חובה לשלוח
    required this.position, // חובה לשלוח
    required this.size, // חובה לשלוח
    required this.confidence, // חובה לשלוח
    required this.changeRate, // חובה לשלוח
    required this.velocity, // חובה לשלוח
  });
}

/// ספים לסינון ולזיהוי התקרבות.
class _RiskThresholds { // מחלקה פרטית שמגדירה ספים
  final double approachingChangeRate; // סף קצב שינוי להתקרבות
  final double approachingVelocity; // סף מהירות להתקרבות
  final double minConfidence; // ביטחון מינימלי

  const _RiskThresholds({ // קונסטרקטור קבוע
    required this.approachingChangeRate, // חובה
    required this.approachingVelocity, // חובה
    required this.minConfidence, // חובה
  });
}

/// מידע היסטורי על אובייקט מפריים קודם.
class _ObjectHistory { // מחלקה פרטית שמאחסנת היסטוריה של אובייקט
  final double area; // שטח האובייקט בפריים הקודם
  final double centerX; // מיקום מרכז X בפריים הקודם
  final double centerY; // מיקום מרכז Y בפריים הקודם
  final double previousScore; // ציון סיכון בפריים הקודם
  final DateTime lastSeen; // זמן אחרון שנראה

  const _ObjectHistory({ // קונסטרקטור קבוע
    required this.area, // חובה
    required this.centerX, // חובה
    required this.centerY, // חובה
    required this.previousScore, // חובה
    required this.lastSeen, // חובה
  });
}