import 'package:flutter/foundation.dart';
import '../models/detection.dart';

class RiskScoringService {

  double _imageWidth  = 640;
  double _imageHeight = 480;

  final Map<String, _ObjectHistory> _history = {};
  DateTime _lastCleanup = DateTime.now();
  static const _cleanupInterval = Duration(seconds: 30);

  // ── משקלים – קלים לכוונון עתידי ────────────────────────
  static const _weights = _RiskWeights(
    objectType : 0.32,
    position   : 0.28,
    size       : 0.18,
    confidence : 0.12, // confidence תורם ישירות לציון
    changeRate : 0.06,
    velocity   : 0.04,
  );

  // ── ספים – קלים לכוונון עתידי ───────────────────────────
  static const _thresholds = _RiskThresholds(
    approachingChangeRate : 8.0,
    approachingVelocity   : 6.0,
    minConfidence         : 0.30, // סינון זיהויים מתחת ל-30%
  );

  // ════════════════════════════════════════════════════════
  // PUBLIC API
  // ════════════════════════════════════════════════════════

  void updateResolution(int width, int height) {
    if (width <= 0 || height <= 0) return;
    _imageWidth  = width.toDouble();
    _imageHeight = height.toDouble();
  }

  /// מסנן זיהויים חלשים, מחשב ציון סיכון וממיין מהגבוה לנמוך
  List<Detection> scoreDetections(List<Detection> detections) {
    _maybeCleanup();

    final filtered = detections
        .where((d) => d.confidence >= _thresholds.minConfidence)
        .toList();

    final scored = filtered.map(_scoreSingleDetection).toList();
    scored.sort((a, b) => b.riskScore.compareTo(a.riskScore));

    return scored;
  }

  void reset() {
    _history.clear();
    _lastCleanup = DateTime.now();
  }

  // ════════════════════════════════════════════════════════
  // SCORING
  // ════════════════════════════════════════════════════════

  Detection _scoreSingleDetection(Detection detection) {
    try {
      final objectType   = _getObjectTypeWeight(detection.tag);
      final position     = _calculatePositionFactor(detection);
      final size         = _calculateSizeFactor(detection);
      final confidence   = _calculateConfidenceFactor(detection);
      final changeRate   = _calculateChangeRateFactor(detection);
      final velocity     = _calculateVelocityFactor(detection);

      final rawRisk =
          (objectType  * _weights.objectType)  +
              (position    * _weights.position)    +
              (size        * _weights.size)        +
              (confidence  * _weights.confidence)  +
              (changeRate  * _weights.changeRate)  +
              (velocity    * _weights.velocity);

      final isApproaching =
          changeRate >= _thresholds.approachingChangeRate ||
              velocity   >= _thresholds.approachingVelocity;

      final key           = _getInstanceKey(detection);
      final previousScore = _history[key]?.previousScore ?? rawRisk;

      // Alpha דינמי: רספונסיבי לסכנה, חלק לרעש
      final smoothed = _smoothScore(
        rawRisk,
        previousScore,
        alpha: isApproaching ? 0.65 : 0.45,
      ).clamp(0.0, 100.0);

      _history[key] = _ObjectHistory(
        area          : detection.area,
        centerX       : detection.centerX,
        centerY       : detection.centerY,
        previousScore : smoothed,
        lastSeen      : DateTime.now(),
      );

      return detection.copyWith(riskScore: smoothed, isApproaching: isApproaching);

    } catch (e, stack) {
      _debug('score error for ${detection.tag}: $e\n$stack');
      // ציון שמרני בשגיאה – לא מתריע שווא
      return detection.copyWith(riskScore: 40.0, isApproaching: false);
    }
  }

  // ════════════════════════════════════════════════════════
  // FACTORS
  // ════════════════════════════════════════════════════════

  double _calculateSizeFactor(Detection d) {
    final imageArea = _imageWidth * _imageHeight;
    if (imageArea <= 0) return 40.0;
    return ((d.area / imageArea).clamp(0.0, 1.0) * 100);
  }

  double _calculatePositionFactor(Detection d) {
    final normX = (d.centerX / _imageWidth).clamp(0.0, 1.0);
    final normY = (d.centerY / _imageHeight).clamp(0.0, 1.0);

    // מרכז + תחתון = מסוכן יותר
    final xFactor = (1.0 - (normX - 0.5).abs() * 2.0).clamp(0.0, 1.0);
    final yFactor = normY;

    return ((xFactor * 0.45 + yFactor * 0.55) * 100).clamp(0.0, 100.0);
  }

  double _calculateConfidenceFactor(Detection d) =>
      (d.confidence * 100).clamp(0.0, 100.0);

  double _calculateChangeRateFactor(Detection d) {
    final prevArea = _history[_getInstanceKey(d)]?.area;
    if (prevArea == null || prevArea <= 0) return 0.0;
    final ratio = (d.area - prevArea) / prevArea;
    return ratio > 0 ? (ratio * 100).clamp(0.0, 100.0) : 0.0;
  }

  double _calculateVelocityFactor(Detection d) {
    final prevY = _history[_getInstanceKey(d)]?.centerY;
    if (prevY == null || _imageHeight <= 0) return 0.0;
    final normalized = (d.centerY - prevY) / _imageHeight;
    return normalized > 0 ? (normalized * 100).clamp(0.0, 100.0) : 0.0;
  }

  double _getObjectTypeWeight(String tag) => switch (tag) {
    'car' || 'bus' || 'truck' || 'train' || 'motorcycle'                    => 100.0,
    'person' || 'bicycle' || 'skateboard' || 'scooter'                      => 88.0,
    'traffic light' || 'crosswalk' || 'stop sign'                           => 72.0,
    'dog' || 'cat' || 'horse' || 'sheep' || 'cow' ||
    'elephant' || 'bear' || 'zebra' || 'giraffe'                            => 68.0,
    'bench' || 'chair' || 'couch' || 'bed' || 'dining table' || 'potted plant' => 52.0,
    'backpack' || 'handbag' || 'suitcase' || 'umbrella'                     => 36.0,
    'skis' || 'sports ball' || 'surfboard' ||
    'tennis racket' || 'bird' || 'fire hydrant'                             => 22.0,
    _                                                                        => 15.0,
  };

  // ════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════

  /// gridSize=60 → מעקב יציב יותר מ-40
  String _getInstanceKey(Detection d) {
    const gridSize = 60.0;
    return '${d.tag}_${d.centerX ~/ gridSize}_${d.centerY ~/ gridSize}';
  }

  double _smoothScore(double current, double previous, {double alpha = 0.5}) =>
      alpha * current + (1 - alpha) * previous;

  void _maybeCleanup() {
    final now = DateTime.now();
    if (now.difference(_lastCleanup) < _cleanupInterval) return;
    final cutoff = now.subtract(const Duration(seconds: 30));
    _history.removeWhere((_, h) => h.lastSeen.isBefore(cutoff));
    _lastCleanup = now;
  }

  void _debug(String msg) {
    if (!kDebugMode) return;
    final t = DateTime.now().toIso8601String().split('T').last.split('.').first;
    debugPrint('[RiskScoring][$t] $msg');
  }
}

// ════════════════════════════════════════════════════════
// DATA CLASSES
// ════════════════════════════════════════════════════════

class _RiskWeights {
  final double objectType, position, size, confidence, changeRate, velocity;
  const _RiskWeights({
    required this.objectType,
    required this.position,
    required this.size,
    required this.confidence,
    required this.changeRate,
    required this.velocity,
  });
}

class _RiskThresholds {
  final double approachingChangeRate, approachingVelocity, minConfidence;
  const _RiskThresholds({
    required this.approachingChangeRate,
    required this.approachingVelocity,
    required this.minConfidence,
  });
}

class _ObjectHistory {
  final double area, centerX, centerY, previousScore;
  final DateTime lastSeen;

  const _ObjectHistory({
    required this.area,
    required this.centerX,
    required this.centerY,
    required this.previousScore,
    required this.lastSeen,
  });
}