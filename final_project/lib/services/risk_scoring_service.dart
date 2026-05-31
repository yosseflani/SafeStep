import 'package:flutter/foundation.dart';
import '../models/detection.dart';

class RiskScoringService {
  double _imageWidth = 640;
  double _imageHeight = 480;

  final Map<String, _ObjectHistory> _history = {};
  DateTime _lastCleanup = DateTime.now();
  static const _cleanupInterval = Duration(seconds: 30);

  // ✅ קבועים מכווננים – קלים לשינוי עתידי
  static const _weights = RiskWeights(
    objectType: 0.32,
    position: 0.28,
    size: 0.18,
    confidence: 0.12,  // ✅ קריטי לדיוק
    changeRate: 0.06,
    velocity: 0.04,
  );

  // ✅ ✅ ✅ השינוי כאן: minConfidence שונה מ-0.25 ל-0.50 (50%) ✅ ✅ ✅
  static const _thresholds = RiskThresholds(
    approachingChangeRate: 8.0,
    approachingVelocity: 6.0,
    minConfidence: 0.50,          // ← שונה מ-0.25 ל-0.50
  );

  void updateResolution(int width, int height) {
    if (width <= 0 || height <= 0) return;
    _imageWidth = width.toDouble();
    _imageHeight = height.toDouble();
  }

  List<Detection> scoreDetections(List<Detection> detections) {
    _maybeCleanup();

    // ✅ מסנן זיהויים עם פחות מ-50% ביטחון (מונע רעש והתראות שווא)
    final filtered = detections.where((d) =>
    d.confidence >= _thresholds.minConfidence  // ← עכשיו 0.50 = 50%
    ).toList();

    final scored = filtered.map(_scoreSingleDetection).toList();
    scored.sort((a, b) => b.riskScore.compareTo(a.riskScore));

    return scored;
  }

  Detection _scoreSingleDetection(Detection detection) {
    try {
      final sizeFactor = _calculateSizeFactor(detection);
      final positionFactor = _calculatePositionFactor(detection);
      final objectTypeWeight = _getObjectTypeWeight(detection.tag);
      final confidenceFactor = _calculateConfidenceFactor(detection);
      final changeRateFactor = _calculateChangeRateFactor(detection);
      final velocityFactor = _calculateVelocityFactor(detection);

      // ✅ נוסחה עם כל 6 הפקטורים + משקלים מכווננים
      final rawRisk =
          (objectTypeWeight * _weights.objectType) +
              (positionFactor * _weights.position) +
              (sizeFactor * _weights.size) +
              (confidenceFactor * _weights.confidence) +
              (changeRateFactor * _weights.changeRate) +
              (velocityFactor * _weights.velocity);

      // ✅ סף גבוה יותר ל-`isApproaching` = פחות התראות שווא
      final bool isApproaching =
          changeRateFactor >= _thresholds.approachingChangeRate ||
              velocityFactor >= _thresholds.approachingVelocity;

      final key = _getInstanceKey(detection);
      final previousScore = _history[key]?.previousScore ?? rawRisk;

      // ✅ Alpha דינמי: רספונסיבי לסכנה, חלק לרעש
      final smoothedScore = _smoothScore(
        rawRisk,
        previousScore,
        alpha: isApproaching ? 0.65 : 0.45,
      ).clamp(0.0, 100.0);

      // ✅ שמירת היסטוריה לעדכון עתידי
      _history[key] = _ObjectHistory(
        area: detection.area,
        centerX: detection.centerX,
        centerY: detection.centerY,
        previousScore: smoothedScore,
        lastSeen: DateTime.now(),
      );

      return detection.copyWith(
        riskScore: smoothedScore,
        isApproaching: isApproaching,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ RISK ERROR: ${detection.tag} - $e');
        debugPrint('STACK: $stack');
      }
      // ✅ ציון שמרני בשגיאה (לא מתריע שווא)
      return detection.copyWith(riskScore: 40.0, isApproaching: false);
    }
  }

  double _calculateSizeFactor(Detection d) {
    final imageArea = _imageWidth * _imageHeight;
    if (imageArea <= 0) return 40.0;
    final normalized = (d.area / imageArea).clamp(0.0, 1.0);
    return (normalized * 100).clamp(0.0, 100.0);
  }

  double _calculatePositionFactor(Detection d) {
    final normX = (d.centerX / _imageWidth).clamp(0.0, 1.0);
    final normY = (d.centerY / _imageHeight).clamp(0.0, 1.0);

    // ✅ מיקום: מרכז + תחתון = מסוכן יותר
    final distFromCenter = (normX - 0.5).abs() * 2.0;
    final xFactor = (1.0 - distFromCenter).clamp(0.0, 1.0);
    final yFactor = normY;

    return ((xFactor * 0.45 + yFactor * 0.55) * 100).clamp(0.0, 100.0);
  }

  double _calculateConfidenceFactor(Detection d) {
    // ✅ Confidence גבוה = פקטור גבוה (ליניארי)
    return (d.confidence * 100).clamp(0.0, 100.0);
  }

  double _getObjectTypeWeight(String tag) {
    switch (tag) {
      case 'car': case 'bus': case 'truck': case 'train': case 'motorcycle':
      return 100.0;
      case 'person': case 'bicycle': case 'skateboard': case 'scooter':
      return 88.0;
      case 'traffic light': case 'crosswalk': case 'stop sign':
      return 72.0;
      case 'dog': case 'cat': case 'horse': case 'sheep': case 'cow':
      case 'elephant': case 'bear': case 'zebra': case 'giraffe':
      return 68.0;
      case 'bench': case 'chair': case 'couch': case 'bed':
      case 'dining table': case 'potted plant':
      return 52.0;
      case 'backpack': case 'handbag': case 'suitcase': case 'umbrella':
      return 36.0;
      case 'skis': case 'sports ball': case 'surfboard':
      case 'tennis racket': case 'bird': case 'fire hydrant':
      return 22.0;
      default:
        return 15.0;
    }
  }

  double _calculateChangeRateFactor(Detection d) {
    final key = _getInstanceKey(d);
    final prevArea = _history[key]?.area;
    if (prevArea == null || prevArea <= 0) return 0.0;

    final ratio = (d.area - prevArea) / prevArea;
    return ratio > 0 ? (ratio * 100).clamp(0.0, 100.0) : 0.0;
  }

  double _calculateVelocityFactor(Detection d) {
    final key = _getInstanceKey(d);
    final prevY = _history[key]?.centerY;
    if (prevY == null || _imageHeight <= 0) return 0.0;

    final deltaY = d.centerY - prevY;
    final normalized = deltaY / _imageHeight;
    return normalized > 0 ? (normalized * 100).clamp(0.0, 100.0) : 0.0;
  }

  String _getInstanceKey(Detection d) {
    // ✅ gridSize=60 = מעקב יציב יותר
    const gridSize = 60.0;
    final gridX = d.centerX ~/ gridSize;
    final gridY = d.centerY ~/ gridSize;
    return '${d.tag}_${gridX}_$gridY';
  }

  double _smoothScore(double current, double previous, {double alpha = 0.5}) {
    return alpha * current + (1 - alpha) * previous;
  }

  void _maybeCleanup() {
    final now = DateTime.now();
    if (now.difference(_lastCleanup) < _cleanupInterval) return;

    final cutoff = now.subtract(const Duration(seconds: 30));
    _history.removeWhere((_, h) => h.lastSeen.isBefore(cutoff));
    _lastCleanup = now;
  }

  void reset() {
    _history.clear();
    _lastCleanup = DateTime.now();
  }
}

// ✅ מבנים מכווננים – קלים לשינוי בלי לגעת בלוגיקה
class RiskWeights {
  final double objectType, position, size, confidence, changeRate, velocity;
  const RiskWeights({
    required this.objectType, required this.position, required this.size,
    required this.confidence, required this.changeRate, required this.velocity,
  });
}

class RiskThresholds {
  final double approachingChangeRate, approachingVelocity, minConfidence;
  const RiskThresholds({
    required this.approachingChangeRate,
    required this.approachingVelocity,
    required this.minConfidence,  // ← עכשיו 0.50
  });
}

class _ObjectHistory {
  final double area, centerX, centerY, previousScore;
  final DateTime lastSeen;
  _ObjectHistory({
    required this.area, required this.centerX, required this.centerY,
    required this.previousScore, required this.lastSeen,
  });
}