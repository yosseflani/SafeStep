import 'package:flutter/foundation.dart';
// ייבוא כלים בסיסיים כמו debugPrint ו-kDebugMode

import '../models/detection.dart';
// ייבוא מודל Detection שעליו מחשבים את ציון הסיכון

/// שירות לחישוב ציון סיכון לזיהויים
/// הציון נע בין 0 (בטוח) ל-100 (סכנה מיידית)
/// ומתבסס על: גודל, מיקום, סוג אובייקט, קצב שינוי וכיוון תנועה
class RiskScoringService {
  // מחלקה שאחראית לחשב riskScore לכל Detection

  double _imageWidth = 640;
  double _imageHeight = 480;
  // רוחב וגובה התמונה

  final Map<String, _ObjectHistory> _history = {};
  // שומר היסטוריה של אובייקטים

  DateTime _lastCleanup = DateTime.now();
  static const _cleanupInterval = Duration(seconds: 30);

  void updateResolution(int width, int height) {
    assert(width > 0 && height > 0);

    _imageWidth = width.toDouble();
    _imageHeight = height.toDouble();
  }

  /// מחשב ציון סיכון ומוסיף גם מידע על התקרבות
  List<Detection> scoreDetections(List<Detection> detections) {
    _maybeCleanup();

    final scored = detections.map(_scoreSingleDetection).toList();

    scored.sort((a, b) => b.riskScore.compareTo(a.riskScore));

    return scored;
  }

  Detection _scoreSingleDetection(Detection detection) {
    try {
      final sizeFactor = _calculateSizeFactor(detection);
      final positionFactor = _calculatePositionFactor(detection);
      final objectTypeWeight = _getObjectTypeWeight(detection.tag);

      final changeRateFactor = _calculateChangeRateFactor(detection);
      // כמה האובייקט גדל → האם מתקרב

      final velocityFactor = _calculateVelocityFactor(detection);
      // האם האובייקט זז כלפי מטה במסך (כלומר מתקרב)

      final riskScore =
          (objectTypeWeight * 0.40) +
              (positionFactor * 0.35) +
              (sizeFactor * 0.15) +
              (changeRateFactor * 0.07) +
              (velocityFactor * 0.03);

      // -------------------------------
      // 🔥 חידוש: בדיקה האם האובייקט מתקרב
      // -------------------------------

      final bool isApproaching =
          changeRateFactor >= 3 || velocityFactor >= 3;
      // סף נמוך יותר = מזהה התקרבות מוקדם יותר

      final key = _getInstanceKey(detection);

      final smoothedScore = _smoothScore(
        riskScore,
        _history[key]?.previousScore ?? riskScore,
      );

      _history[key] = _ObjectHistory(
        area: detection.area,
        centerX: detection.centerX,
        centerY: detection.centerY,
        previousScore: smoothedScore,
        lastSeen: DateTime.now(),
      );

      return detection.copyWith(
        riskScore: smoothedScore.clamp(0.0, 100.0),
        isApproaching: isApproaching, // 👈 חדש
      );

    } catch (e) {
      if (kDebugMode) debugPrint('RiskScoring error: $e');

      return detection.copyWith(
        riskScore: 50.0,
        isApproaching: false,
      );
    }
  }

  double _calculateSizeFactor(Detection detection) {
    final imageArea = _imageWidth * _imageHeight;

    if (imageArea <= 0) return 50.0;

    final normalizedArea = (detection.area / imageArea).clamp(0.0, 1.0);

    return normalizedArea * 100;
  }

  double _calculatePositionFactor(Detection detection) {
    final normalizedX = (detection.centerX / _imageWidth).clamp(0.0, 1.0);
    final normalizedY = (detection.centerY / _imageHeight).clamp(0.0, 1.0);

    final distanceFromCenter = (normalizedX - 0.5).abs() * 2;

    final xFactor = 1.0 - (distanceFromCenter * 0.75);
    final yFactor = normalizedY;

    return ((xFactor * 0.3 + yFactor * 0.7) * 100).clamp(0.0, 100.0);
  }

  double _getObjectTypeWeight(String tag) {
    switch (tag) {
      case 'car':
      case 'bus':
      case 'truck':
      case 'train':
      case 'motorcycle':
        return 100;

      case 'person':
      case 'bicycle':
      case 'skateboard':
        return 90;

      case 'traffic light':
      case 'stop sign':
        return 75;

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

      case 'bench':
      case 'chair':
      case 'couch':
      case 'bed':
      case 'dining table':
      case 'potted plant':
        return 50;

      case 'backpack':
      case 'handbag':
      case 'suitcase':
      case 'umbrella':
        return 35;

      case 'skis':
      case 'sports ball':
      case 'surfboard':
      case 'tennis racket':
      case 'bird':
      case 'fire hydrant':
        return 20;

      default:
        return 10;
    }
  }

  double _calculateChangeRateFactor(Detection detection) {
    final key = _getInstanceKey(detection);

    final previousArea = _history[key]?.area;

    if (previousArea == null || previousArea <= 0) return 0.0;

    final ratio = (detection.area - previousArea) / previousArea;

    final clampedRatio = ratio.clamp(-1.0, 1.0);

    return clampedRatio > 0 ? clampedRatio * 100 : 0.0;
  }

  double _calculateVelocityFactor(Detection detection) {
    final key = _getInstanceKey(detection);

    final previousY = _history[key]?.centerY;

    if (previousY == null) return 0.0;

    final deltaY = detection.centerY - previousY;

    final normalizedDelta = (deltaY / _imageHeight).clamp(-1.0, 1.0);

    return normalizedDelta > 0 ? normalizedDelta * 100 : 0.0;
  }

  String _getInstanceKey(Detection detection) {
    const gridSize = 40.0;

    final gridX = (detection.centerX ~/ gridSize);
    final gridY = (detection.centerY ~/ gridSize);

    return '${detection.tag}_${gridX}_$gridY';
  }

  double _smoothScore(double current, double previous, {double alpha = 0.5}) {
    return alpha * current + (1 - alpha) * previous;
  }

  void _maybeCleanup() {
    final now = DateTime.now();

    if (now.difference(_lastCleanup) < _cleanupInterval) return;

    final cutoff = now.subtract(const Duration(seconds: 30));

    _history.removeWhere((_, history) => history.lastSeen.isBefore(cutoff));

    _lastCleanup = now;
  }

  void reset() {
    _history.clear();
    _lastCleanup = DateTime.now();
  }
}

class _ObjectHistory {
  final double area;
  final double centerX;
  final double centerY;
  final double previousScore;
  final DateTime lastSeen;

  _ObjectHistory({
    required this.area,
    required this.centerX,
    required this.centerY,
    required this.previousScore,
    required this.lastSeen,
  });
}