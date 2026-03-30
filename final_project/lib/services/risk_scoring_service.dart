import '../models/detection.dart';

class RiskScoringService {
  final Map<String, double> _previousAreasByTag = {};

  // מקבלת רשימת זיהויים מחשבת risk score וממיינת
  List<Detection> scoreDetections(List<Detection> detections) {
    return detections.map(_scoreSingleDetection).toList()
      ..sort((a, b) => b.riskScore.compareTo(a.riskScore));
  }

  Detection _scoreSingleDetection(Detection detection) {
    final sizeFactor = _calculateSizeFactor(detection);
    final positionFactor = _calculatePositionFactor(detection);
    final objectTypeWeight = _getObjectTypeWeight(detection.tag);
    final changeRateFactor = _calculateChangeRateFactor(detection);

    final riskScore =
        (sizeFactor * 0.35) +
            (positionFactor * 0.25) +
            (objectTypeWeight * 0.25) +
            (changeRateFactor * 0.15);

    return detection.copyWith(riskScore: riskScore);
  }

  // הופך את השטח לציון נוח לעבודה
  double _calculateSizeFactor(Detection detection) {
    final normalizedArea = (detection.area / (640 * 640)).clamp(0.0, 1.0);
    return normalizedArea * 100;
  }

  // מחשב מרחק ממרכז המסך
  double _calculatePositionFactor(Detection detection) {
    final centerDistanceFromMiddle = (detection.centerX - 320).abs();
    final closenessToCenter = 1 - (centerDistanceFromMiddle / 320).clamp(0.0, 1.0);
    return closenessToCenter * 100;
  }

  // סיווג לפי סכנה - אפשר לשנות
  double _getObjectTypeWeight(String tag) {
    switch (tag) {
      case 'car':
      case 'bus':
      case 'truck':
      case 'motorcycle':
        return 100;
      case 'person':
      case 'bicycle':
        return 80;
      case 'traffic light':
      case 'stop sign':
        return 60;
      default:
        return 40;
    }
  }

  // בודק האם האובייקט גדל ביחס לפריים הקודם
  double _calculateChangeRateFactor(Detection detection) {
    final currentArea = detection.area;
    final previousArea = _previousAreasByTag[detection.tag] ?? currentArea;

    _previousAreasByTag[detection.tag] = currentArea;

    if (previousArea <= 0) return 0;

    final ratio = ((currentArea - previousArea) / previousArea).clamp(-1.0, 1.0);
    final approachingScore = ratio > 0 ? ratio * 100 : 0.0;
    return approachingScore;
  }
}