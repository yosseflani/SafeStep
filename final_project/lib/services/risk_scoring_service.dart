import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/detection.dart';

/// שירות לחישוב ציון סיכון עבור אובייקטים שזוהו.
class RiskScoringService {
  double _imageWidth = 640;
  double _imageHeight = 480;

  // היסטוריית אובייקטים מפריימים קודמים.
  final Map<String, _ObjectHistory> _history = {};

  DateTime _lastCleanup = DateTime.now();

  // פרק הזמן לניקוי היסטוריה ישנה.
  static const _cleanupInterval = Duration(seconds: 30);

  // גודל תא למעקב מקורב אחר אותו אובייקט.
  static const double _gridSize = 60.0;

  // משקלים לחישוב ציון הסיכון הסופי.
  static const _weights = _RiskWeights(
    objectType: 0.30,
    position: 0.22,
    size: 0.14,
    confidence: 0.10,
    changeRate: 0.14,
    velocity: 0.10,
  );

  // ספים לסינון זיהויים ולזיהוי התקרבות.
  static const _thresholds = _RiskThresholds(
    approachingChangeRate: 8.0,
    approachingVelocity: 6.0,
    minConfidence: 0.30,
  );

  /// מעדכן את רזולוציית התמונה עבור חישובי מיקום וגודל.
  void updateResolution(int width, int height) {
    if (width <= 0 || height <= 0) return;

    _imageWidth = width.toDouble();
    _imageHeight = height.toDouble();
  }

  /// מחשב ציון סיכון לכל זיהוי ומחזיר רשימה ממוינת לפי מסוכנות.
  List<Detection> scoreDetections(List<Detection> detections) {
    _maybeCleanup();

    final filtered = detections
        .where((d) => d.confidence >= _thresholds.minConfidence)
        .toList();

    final scored = filtered.map(_scoreSingleDetection).toList();

    scored.sort((a, b) => b.riskScore.compareTo(a.riskScore));

    return scored;
  }

  /// מאפס את היסטוריית המעקב.
  void reset() {
    _history.clear();
    _lastCleanup = DateTime.now();
  }

  /// מחשב ציון סיכון עבור זיהוי יחיד.
  Detection _scoreSingleDetection(Detection detection) {
    try {
      final objectType = _getObjectTypeWeight(detection.tag);
      final position = _calculatePositionFactor(detection);
      final size = _calculateSizeFactor(detection);
      final confidence = _calculateConfidenceFactor(detection);
      final changeRate = _calculateChangeRateFactor(detection);
      final velocity = _calculateVelocityFactor(detection);

      // סכום משוקלל של כל גורמי הסיכון.
      final rawRisk =
          (objectType * _weights.objectType) +
              (position * _weights.position) +
              (size * _weights.size) +
              (confidence * _weights.confidence) +
              (changeRate * _weights.changeRate) +
              (velocity * _weights.velocity);

      // התקרבות מזוהה לפי גדילה בשטח או תנועה כלפי תחתית התמונה.
      final isApproaching =
          changeRate >= _thresholds.approachingChangeRate ||
              velocity >= _thresholds.approachingVelocity;

      final key = _getInstanceKey(detection);
      final previousScore = _history[key]?.previousScore ?? rawRisk;

      // החלקת הציון מפחיתה קפיצות חדות בין פריימים.
      final smoothed = _smoothScore(
        rawRisk,
        previousScore,
        alpha: isApproaching ? 0.70 : 0.45,
      ).clamp(0.0, 100.0);

      // שמירת נתוני האובייקט לפריים הבא.
      _history[key] = _ObjectHistory(
        area: detection.area,
        centerX: detection.centerX,
        centerY: detection.centerY,
        previousScore: smoothed,
        lastSeen: DateTime.now(),
      );

      return detection.copyWith(
        riskScore: smoothed,
        isApproaching: isApproaching,
      );
    } catch (e, stack) {
      _debug('score error for ${detection.tag}: $e\n$stack');

      return detection.copyWith(
        riskScore: 30.0,
        isApproaching: false,
      );
    }
  }

  /// מחזיר ציון בסיסי לפי סוג האובייקט.
  double _getObjectTypeWeight(String tag) => switch (tag) {
    'car' || 'motorcycle' => 100.0,
    'pole' => 88.0,
    'person' => 78.0,
    'bench' || 'couch' => 55.0,
    'crosswalk' => 35.0,
    _ => 15.0,
  };

  /// מחשב סיכון לפי מיקום האובייקט בתמונה.
  double _calculatePositionFactor(Detection d) {
    if (_imageWidth <= 0 || _imageHeight <= 0) return 30.0;

    final normX = (d.centerX / _imageWidth).clamp(0.0, 1.0);
    final normY = (d.centerY / _imageHeight).clamp(0.0, 1.0);

    final xFactor = (1.0 - (normX - 0.5).abs() * 2.0).clamp(0.0, 1.0);

    final yFactor = normY;

    return ((xFactor * 0.40 + yFactor * 0.60) * 100).clamp(0.0, 100.0);
  }


  /// מחשב סיכון לפי גודל האובייקט ביחס לתמונה.
  double _calculateSizeFactor(Detection d) {
    final imageArea = _imageWidth * _imageHeight;

    if (imageArea <= 0) return 30.0;

    // יחס שטח האובייקט לשטח התמונה.
    final ratio = (d.area / imageArea).clamp(1e-6, 1.0);

    // שימוש בסקאלה לוגריתמית לאיזון בין אובייקטים קטנים וגדולים.
    final logRatio = log(ratio) / ln10;

    return (((logRatio + 6.0) / 6.0).clamp(0.0, 1.0) * 100);
  }

  /// ממיר את רמת הביטחון לציון בין 0 ל־100.
  double _calculateConfidenceFactor(Detection d) {
    return (d.confidence * 100).clamp(0.0, 100.0);
  }

  /// מחשב גידול בשטח האובייקט ביחס לפריים הקודם.
  double _calculateChangeRateFactor(Detection d) {
    final previous = _history[_getInstanceKey(d)];

    if (previous == null || previous.area <= 0) return 0.0;

    final ratio = (d.area - previous.area) / previous.area;

    return ratio > 0 ? (ratio * 100).clamp(0.0, 100.0) : 0.0;
  }

  /// מחשב תנועה אנכית כלפי תחתית התמונה.
  double _calculateVelocityFactor(Detection d) {
    final previous = _history[_getInstanceKey(d)];

    if (previous == null || _imageHeight <= 0) return 0.0;

    final normalized = (d.centerY - previous.centerY) / _imageHeight;

    return normalized > 0 ? (normalized * 100).clamp(0.0, 100.0) : 0.0;
  }

  /// יוצר מפתח מקורב למעקב אחר אותו אובייקט בין פריימים.
  String _getInstanceKey(Detection d) {
    return '${d.tag}_${d.centerX ~/ _gridSize}_${d.centerY ~/ _gridSize}';
  }

  /// מחליק את ציון הסיכון כדי למנוע קפיצות חדות.
  double _smoothScore(
      double current,
      double previous,
      {
        double alpha = 0.5,
      }) {
    return alpha * current + (1.0 - alpha) * previous;
  }

  /// מנקה מההיסטוריה אובייקטים שלא נראו לאחרונה.
  void _maybeCleanup() {
    final now = DateTime.now();

    if (now.difference(_lastCleanup) < _cleanupInterval) return;

    final cutoff = now.subtract(const Duration(seconds: 30));

    _history.removeWhere((_, h) => h.lastSeen.isBefore(cutoff));

    _lastCleanup = now;
  }

  /// מדפיס לוגים במצב פיתוח בלבד.
  void _debug(String msg) {
    if (!kDebugMode) return;

    final time = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .split('.')
        .first;

    debugPrint('[RiskScoring][$time] $msg');
  }
}

/// משקלים לחישוב ציון הסיכון.
class _RiskWeights {
  final double objectType;
  final double position;
  final double size;
  final double confidence;
  final double changeRate;
  final double velocity;

  const _RiskWeights({
    required this.objectType,
    required this.position,
    required this.size,
    required this.confidence,
    required this.changeRate,
    required this.velocity,
  });
}

/// ספי סינון וזיהוי התקרבות.
class _RiskThresholds {
  final double approachingChangeRate;
  final double approachingVelocity;
  final double minConfidence;

  const _RiskThresholds({
    required this.approachingChangeRate,
    required this.approachingVelocity,
    required this.minConfidence,
  });
}

/// מידע היסטורי על אובייקט מפריים קודם.
class _ObjectHistory {
  final double area;
  final double centerX;
  final double centerY;
  final double previousScore;
  final DateTime lastSeen;

  const _ObjectHistory({
    required this.area,
    required this.centerX,
    required this.centerY,
    required this.previousScore,
    required this.lastSeen,
  });
}