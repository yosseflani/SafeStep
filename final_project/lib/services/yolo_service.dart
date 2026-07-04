import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';

import '../models/detection.dart';
import '../utils/logger.dart';

/// שירות לזיהוי אובייקטים באמצעות מודל YOLO.
class YoloService {
  // מופע הספרייה שמריצה את מודל הזיהוי.
  final FlutterVision _vision = FlutterVision();
  final _log = const AppLogger('YoloService');

  // מציין האם המודל נטען ומוכן לשימוש.
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // ספי הזיהוי של המודל.
  static const double _iouThreshold = 0.4;
  static const double _confThreshold = 0.35;
  static const double _classThreshold = 0.35;

  // תגיות רלוונטיות למערכת ההתראות.
  static const Set<String> allowedTags = {
    'crosswalk',
    'person',
    'car',
    'motorcycle',
    'pole',
    'couch',
    'bench',
  };

  /// טוען את מודל YOLO וקובץ התוויות.
  Future<void> initModel() async {
    _log.debug('initModel()');

    if (_isLoaded) {
      _log.debug('Model already loaded');
      return;
    }

    try {
      await _vision.loadYoloModel(
        labels: 'assets/safestep_labels.txt',
        modelPath: 'assets/safestep_yolo.tflite',
        modelVersion: 'yolov8',
        numThreads: 2,
        useGpu: false,
      );

      _isLoaded = true;

      _log.debug('Model loaded successfully');
    } catch (e, stack) {
      _isLoaded = false;

      _log.debug('Model load failed: $e\n$stack');
      rethrow;
    }
  }

  /// מריץ זיהוי על פריים מהמצלמה.
  Future<List<Detection>> detectObjects(
      List<Uint8List> bytesList,
      int imageHeight,
      int imageWidth,
      {
        double? confThreshold,
      }) async {
    if (!isLoaded || bytesList.isEmpty || imageHeight <= 0 || imageWidth <= 0) {
      _log.debug('Invalid input or model not loaded');
      return const [];
    }

    // שימוש בסף מותאם אם נשלח, אחרת בברירת המחדל.
    final activeConf = confThreshold ?? _confThreshold;

    try {
      final results = await _vision.yoloOnFrame(
        bytesList: bytesList,
        imageHeight: imageHeight,
        imageWidth: imageWidth,
        iouThreshold: _iouThreshold,
        confThreshold: activeConf,
        classThreshold: _classThreshold,
      );

      final detections = <Detection>[];

      // מוני סינון לצורכי Debug.
      int filteredByTag = 0;
      int filteredByBox = 0;
      int filteredByConf = 0;

      for (final raw in results) {
        final tag = (raw['tag'] ?? '').toString().trim().toLowerCase();
        final rawBox = (raw['box'] as List?) ?? const [];

        if (tag.isEmpty) continue;

        if (rawBox.length < 5) {
          filteredByBox++;
          continue;
        }

        final confidence = (rawBox[4] as num).toDouble();

        if (confidence < activeConf) {
          filteredByConf++;
          continue;
        }

        if (!allowedTags.contains(tag)) {
          filteredByTag++;
          continue;
        }

        // המרת תוצאת YOLO לאובייקט פנימי של האפליקציה.
        detections.add(
          Detection(
            tag: tag,
            confidence: confidence,
            box: [
              (rawBox[0] as num).toDouble(),
              (rawBox[1] as num).toDouble(),
              (rawBox[2] as num).toDouble(),
              (rawBox[3] as num).toDouble(),
            ],
          ),
        );
      }

      if (kDebugMode && results.isNotEmpty) {
        _log.debug(
          'raw=${results.length} accepted=${detections.length} '
              '(filtered: tag=$filteredByTag '
              'conf=$filteredByConf box=$filteredByBox)',
        );
      }

      return detections;
    } catch (e, stack) {
      _log.debug('Detection error: $e\n$stack');
      return const [];
    }
  }

  /// סוגר את מודל הזיהוי ומשחרר משאבים.
  Future<void> dispose() async {
    if (!isLoaded) return;

    try {
      await _vision.closeYoloModel();
      _isLoaded = false;

      _log.debug('Model closed');
    } catch (e, stack) {
      _log.debug('Dispose error: $e\n$stack');
    }
  }

  /// מחזיר מידע בסיסי לצורכי בדיקה.
  Map<String, dynamic> getDebugInfo() => {
    'isLoaded': isLoaded,
    'iouThreshold': _iouThreshold,
    'confThreshold': _confThreshold,
    'classThreshold': _classThreshold,
    'allowedTagsCount': allowedTags.length,
  };

}