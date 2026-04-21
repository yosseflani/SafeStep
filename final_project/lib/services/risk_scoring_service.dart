import 'package:flutter/foundation.dart';
// ייבוא כלים בסיסיים כמו debugPrint ו-kDebugMode

import '../models/detection.dart';
// ייבוא מודל Detection שעליו מחשבים את ציון הסיכון

/// שירות לחישוב ציון סיכון לזיהויים
/// הציון נע בין 0 (בטוח) ל-100 (סכנה מיידית)
/// ומתבסס על: גודל, מיקום, סוג אובייקט, קצב שינוי וכיוון תנועה
class RiskScoringService {
  // מחלקה שאחראית לחשב riskScore לכל Detection

  // רזולוציית תמונה דינמית - חובה לעדכן לפני חישוב ציונים
  double _imageWidth = 640;
  double _imageHeight = 480;
  // רוחב וגובה התמונה, משמשים לנרמול מיקום וגודל

  // מעקב אחר אובייקטים לפי מפתח ייחודי
  final Map<String, _ObjectHistory> _history = {};
  // שומר מידע מהעבר על כל אובייקט כדי למדוד שינוי ותנועה

  // ניקוי היסטוריה ישנה כל 30 שניות
  DateTime _lastCleanup = DateTime.now();
  static const _cleanupInterval = Duration(seconds: 30);
  // שומר מתי בוצע ניקוי אחרון, כדי לא לנקות כל הזמן

  /// עדכון רזולוציית התמונה - חובה לקרוא עם מידות ה-CameraImage האמיתיות
  void updateResolution(int width, int height) {
    assert(width > 0 && height > 0, 'Invalid resolution: ${width}x$height');
    // בודק שהרזולוציה תקינה

    _imageWidth = width.toDouble();
    _imageHeight = height.toDouble();
    // שומר את המידות כ-double לחישובים בהמשך
  }

  /// מחשב ציון סיכון לרשימת זיהויים וממיין מהמסוכן ביותר לקל ביותר
  List<Detection> scoreDetections(List<Detection> detections) {
    _maybeCleanup();
    // מנקה היסטוריה ישנה אם צריך

    final scored = detections.map(_scoreSingleDetection).toList();
    // מחשב ציון לכל Detection

    scored.sort((a, b) => b.riskScore.compareTo(a.riskScore));
    // ממיין מהמסוכן ביותר לפחות מסוכן

    return scored;
    // מחזיר את הרשימה לאחר חישוב ומיון
  }

  Detection _scoreSingleDetection(Detection detection) {
    try {
      final sizeFactor = _calculateSizeFactor(detection);
      // מחשב סיכון לפי גודל האובייקט

      final positionFactor = _calculatePositionFactor(detection);
      // מחשב סיכון לפי מיקום במסך

      final objectTypeWeight = _getObjectTypeWeight(detection.tag);
      // מחשב משקל לפי סוג האובייקט

      final changeRateFactor = _calculateChangeRateFactor(detection);
      // מחשב האם האובייקט גדל (כלומר מתקרב)

      final velocityFactor = _calculateVelocityFactor(detection);
      // מחשב תנועה אנכית במסך

      final riskScore =
          (objectTypeWeight * 0.35) +
              (positionFactor * 0.30) +
              (sizeFactor * 0.15) +
              (changeRateFactor * 0.12) +
              (velocityFactor * 0.08);
      // משלב את כל הגורמים לציון אחד לפי משקלים

      // החלקה למניעת קפיצות חדות בין פריימים
      final key = _getInstanceKey(detection);
      // בונה מזהה ייחודי לאובייקט

      final smoothedScore = _smoothScore(
        riskScore,
        _history[key]?.previousScore ?? riskScore,
      );
      // מחליק את הציון לפי הציון הקודם כדי למנוע קפיצות חדות

      _history[key] = _ObjectHistory(
        area: detection.area,
        centerX: detection.centerX,
        centerY: detection.centerY,
        previousScore: smoothedScore,
        lastSeen: DateTime.now(),
      );
      // שומר היסטוריה עדכנית של האובייקט

      return detection.copyWith(riskScore: smoothedScore.clamp(0.0, 100.0));
      // מחזיר Detection חדש עם riskScore בין 0 ל-100

    } catch (e) {
      if (kDebugMode) debugPrint('RiskScoring error: $e');
      // מדפיס שגיאה במצב פיתוח

      return detection.copyWith(riskScore: 50.0);
      // במקרה שגיאה מחזיר ציון ביניים קבוע
    }
  }

  /// גודל האובייקט ביחס למסך - ככל שגדול יותר, כך מסוכן יותר
  double _calculateSizeFactor(Detection detection) {
    final imageArea = _imageWidth * _imageHeight;
    // מחשב את שטח התמונה

    if (imageArea <= 0) return 50.0;
    // הגנה במקרה לא תקין

    final normalizedArea = (detection.area / imageArea).clamp(0.0, 1.0);
    // מחשב איזה חלק מהמסך האובייקט תופס

    return normalizedArea * 100;
    // ממיר לציון בין 0 ל-100
  }

  /// מיקום האובייקט - תחתית המסך = קרוב למשתמש = מסוכן יותר
  double _calculatePositionFactor(Detection detection) {
    final normalizedX = (detection.centerX / _imageWidth).clamp(0.0, 1.0);
    // מיקום אופקי מנורמל בין 0 ל-1

    final normalizedY = (detection.centerY / _imageHeight).clamp(0.0, 1.0);
    // מיקום אנכי מנורמל בין 0 ל-1

    final xFactor = 1 - (normalizedX - 0.5).abs() * 2;
    // ככל שהאובייקט קרוב יותר למרכז המסך, הוא מסוכן יותר

    final yFactor = 1 - normalizedY;
    // לפי הכוונה של הכותב: למטה במסך נחשב קרוב יותר

    return ((xFactor * 0.3 + yFactor * 0.7) * 100).clamp(0.0, 100.0);
    // משקלל מיקום אופקי ואנכי לציון אחד
  }

  /// משקל לפי סוג אובייקט
  double _getObjectTypeWeight(String tag) {
    switch (tag) {
    // סכנה מיידית - כלי רכב נעים
      case 'car':
      case 'bus':
      case 'truck':
      case 'train':
      case 'motorcycle':
        return 100;

    // סכנה גבוהה - הולכי רגל וכלים קטנים
      case 'person':
      case 'bicycle':
      case 'skateboard':
        return 90;

    // סכנה בינונית-גבוהה - תשתיות דרך
      case 'traffic light':
      case 'stop sign':
        return 75;

    // סכנה בינונית - בעלי חיים שיכולים לזוז פתאום
      case 'dog':
      case 'cat':
      case 'horse':
      case 'sheep':
      case 'cow':
      case 'elephant':
      case 'bear':
      case 'zebra':
      case 'giraffe':
        return 70;

    // סכנה נמוכה-בינונית - מכשולים נייחים גדולים
      case 'bench':
      case 'chair':
      case 'couch':
      case 'bed':
      case 'dining table':
      case 'potted plant':
        return 50;

    // סכנה נמוכה - חפצים ניידים בינוניים
      case 'backpack':
      case 'handbag':
      case 'suitcase':
      case 'umbrella':
        return 35;

    // סכנה מינימלית - חפצים קטנים
      case 'skis':
      case 'sports ball':
      case 'surfboard':
      case 'tennis racket':
      case 'bird':
      case 'fire hydrant':
        return 20;

      default:
        return 10;
    // ברירת מחדל לאובייקט לא מוכר
    }
  }

  /// קצב שינוי גודל - אובייקט שגדל = מתקרב = מסוכן יותר
  double _calculateChangeRateFactor(Detection detection) {
    final key = _getInstanceKey(detection);
    // מזהה האובייקט

    final previousArea = _history[key]?.area ?? detection.area;
    // לוקח את הגודל הקודם, ואם אין - משתמש בנוכחי

    if (previousArea <= 0) return 50.0;
    // הגנה מחלוקה ב-0 או ערכים לא תקינים

    final ratio = (detection.area - previousArea) / previousArea;
    // מחשב בכמה האובייקט גדל/קטן יחסית לפריים קודם

    final clampedRatio = ratio.clamp(-1.0, 1.0);
    // מגביל את הערך כדי למנוע קפיצות חריגות

    return clampedRatio > 0 ? clampedRatio * 100 : 0.0;
    // רק אם יש גדילה (התקרבות) מחזירים ציון חיובי
  }

  /// כיוון תנועה אנכי - ירידה במסך = מתקרב למשתמש = מסוכן יותר
  double _calculateVelocityFactor(Detection detection) {
    final key = _getInstanceKey(detection);
    // מזהה האובייקט

    final previousY = _history[key]?.centerY;
    // מיקום Y קודם של מרכז האובייקט

    if (previousY == null) return 50.0;
    // אם אין מידע קודם, מחזיר ערך ביניים

    final deltaY = detection.centerY - previousY;
    // שינוי במיקום האנכי

    final normalizedDelta = (deltaY / _imageHeight).clamp(-1.0, 1.0);
    // מנרמל ביחס לגובה התמונה

    return normalizedDelta > 0 ? normalizedDelta * 100 : 0.0;
    // אם האובייקט זז בכיוון שנחשב מסוכן - מחזיר ציון
  }

  /// מפתח ייחודי לאובייקט לפי תג + אזור במסך (רשת 40 פיקסלים)
  String _getInstanceKey(Detection detection) {
    const gridSize = 40.0;
    // גודל התא ברשת

    final gridX = (detection.centerX ~/ gridSize);
    // באיזה תא אופקי נמצא האובייקט

    final gridY = (detection.centerY ~/ gridSize);
    // באיזה תא אנכי נמצא האובייקט

    return '${detection.tag}_${gridX}_$gridY';
    // מפתח ייחודי משוער לפי סוג + מיקום
  }

  /// החלקה אקספוננציאלית למניעת קפיצות חדות בציון
  double _smoothScore(double current, double previous, {double alpha = 0.25}) {
    return alpha * current + (1 - alpha) * previous;
    // משלב ציון חדש עם ציון קודם כדי ליצור מעבר חלק יותר
  }

  /// ניקוי ערכים ישנים מההיסטוריה
  void _maybeCleanup() {
    final now = DateTime.now();
    // הזמן הנוכחי

    if (now.difference(_lastCleanup) < _cleanupInterval) return;
    // אם עדיין לא עבר מספיק זמן - לא מנקה

    final cutoff = now.subtract(const Duration(seconds: 30));
    // כל ערך ישן יותר מ-30 שניות יימחק

    _history.removeWhere((_, history) => history.lastSeen.isBefore(cutoff));
    // מוחק היסטוריה ישנה

    _lastCleanup = now;
    // מעדכן זמן ניקוי אחרון
  }

  /// איפוס היסטוריה - לקרוא כשהמשתמש עוצר ומתחיל מחדש
  void reset() {
    _history.clear();
    // מוחק את כל ההיסטוריה

    _lastCleanup = DateTime.now();
    // מאפס גם את זמן הניקוי
  }
}

/// מחלקת עזר פרטית לשמירת היסטוריית אובייקט בין פריימים
class _ObjectHistory {
  final double area;
  // הגודל הקודם של האובייקט

  final double centerX;
  // מרכז X קודם

  final double centerY;
  // מרכז Y קודם

  final double previousScore;
  // ציון הסיכון הקודם

  final DateTime lastSeen;
  // מתי ראינו את האובייקט לאחרונה

  _ObjectHistory({
    required this.area,
    required this.centerX,
    required this.centerY,
    required this.previousScore,
    required this.lastSeen,
  });
// constructor ששומר את כל הנתונים בהיסטוריה
}