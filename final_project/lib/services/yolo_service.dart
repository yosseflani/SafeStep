import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';
import '../models/detection.dart';

class YoloService {
  final FlutterVision _vision = FlutterVision();
  bool isLoaded = false;

  // ✅ ספים מכווננים – נמוכים כדי לא לאבד זיהויים, הסינון האמיתי ב-RiskScoringService
  static const double _iouThreshold = 0.4;
  static const double _confThreshold = 0.15;  // ✅ חזר ל-15%!
  static const double _classThreshold = 0.15; // ✅ חזר ל-15%!

  // ✅ רשימה מלאה של תגיות מותרות (כמו בגרסה הישנה + אפשר להרחיב)
  static const Set<String> allowedTags = {
    // רכבים ותחבורה
    'car', 'bus', 'truck', 'train', 'motorcycle', 'bicycle', 'scooter',
    // אנשים
    'person',
    // תשתית ותמרורים
    'traffic light', 'stop sign', 'crosswalk', 'fire hydrant', 'bench',
    // בעלי חיים
    'bird', 'cat', 'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe',
    // חפצים אישיים
    'backpack', 'umbrella', 'handbag', 'suitcase',
    // ספורט ופנאי
    'skis', 'sports ball', 'skateboard', 'surfboard', 'tennis racket',
    // ריהוט ובית
    'chair', 'couch', 'potted plant', 'bed', 'dining table',
    // חפצים קטנים
    'vase', 'bottle', 'cup', 'book', 'cell phone', 'tv', 'laptop',
  };

  Future<void> initModel() async {
    if (kDebugMode) debugPrint('🧠 YOLO: initModel() called');
    if (isLoaded) {
      if (kDebugMode) debugPrint('⏭️ YOLO: already loaded, skipping');
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('📦 YOLO: loading model from assets/yolov8n_float32.tflite');
        debugPrint('🏷️  YOLO: loading labels from assets/labels.txt');
      }

      await _vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: 'assets/yolov8n_float32.tflite',
        modelVersion: 'yolov8',
        numThreads: 2,      // ✅ מפורש ליציבות
        useGpu: false,      // ✅ CPU לרוב יציב יותר במובייל
      );

      isLoaded = true;
      if (kDebugMode) debugPrint('✅ YOLO: model loaded successfully');
    } catch (e, stack) {
      isLoaded = false;
      if (kDebugMode) {
        debugPrint('❌ YOLO ERROR: failed to load model');
        debugPrint('❌ YOLO ERROR: $e');
        debugPrint('📋 STACK: $stack');
      }
      rethrow;
    }
  }

  Future<List<Detection>> detectObjects(
      List<Uint8List> bytesList,
      int imageHeight,
      int imageWidth, {
        double? confThreshold,
      }) async {
    if (kDebugMode) {
      debugPrint('🔍 YOLO: detectObjects() | loaded=$isLoaded | planes=${bytesList.length}');
    }

    if (!isLoaded || bytesList.isEmpty || imageHeight <= 0 || imageWidth <= 0) {
      if (kDebugMode) debugPrint('⚠️ YOLO: invalid input or not loaded');
      return const [];
    }

    try {
      final activeConfThreshold = confThreshold ?? _confThreshold;

      if (kDebugMode) {
        debugPrint('⚙️ YOLO: running inference | iou=$_iouThreshold conf=$activeConfThreshold class=$_classThreshold');
      }

      final results = await _vision.yoloOnFrame(
        bytesList: bytesList,
        imageHeight: imageHeight,
        imageWidth: imageWidth,
        iouThreshold: _iouThreshold,
        confThreshold: activeConfThreshold,
        classThreshold: _classThreshold,
      );

      if (kDebugMode) debugPrint('📊 YOLO: raw results = ${results.length}');

      final detections = <Detection>[];
      int filteredByTag = 0;
      int filteredByConfidence = 0;
      int filteredByBox = 0;

      for (final raw in results) {
        final tag = (raw['tag'] ?? '').toString().trim().toLowerCase();
        final rawBox = (raw['box'] as List?) ?? const [];

        if (tag.isEmpty) continue;

        if (rawBox.length < 5) {
          filteredByBox++;
          if (kDebugMode) debugPrint('🗑️ YOLO: skipped "$tag" - invalid box ($rawBox)');
          continue;
        }

        final confidence = (rawBox[4] as num).toDouble();

        if (confidence < activeConfThreshold) {
          filteredByConfidence++;
          if (kDebugMode) {
            debugPrint('🗑️ YOLO: skipped "$tag" - confidence $confidence < $activeConfThreshold');
          }
          continue;
        }

        if (!allowedTags.contains(tag)) {
          filteredByTag++;
          if (kDebugMode) debugPrint('🗑️ YOLO: skipped "$tag" - not in allowedTags');
          continue;
        }

        final box = [
          (rawBox[0] as num).toDouble(),
          (rawBox[1] as num).toDouble(),
          (rawBox[2] as num).toDouble(),
          (rawBox[3] as num).toDouble(),
        ];

        detections.add(Detection(tag: tag, confidence: confidence, box: box));

        if (kDebugMode) {
          debugPrint('✅ YOLO: accepted "$tag" conf=${confidence.toStringAsFixed(3)} box=$box');
        }
      }

      // ✅ סיכום אבחון מפורט
      if (kDebugMode && results.isNotEmpty) {
        debugPrint('📈 YOLO SUMMARY:');
        debugPrint('   raw: ${results.length} | accepted: ${detections.length}');
        debugPrint('   filtered: tag=$filteredByTag conf=$filteredByConfidence box=$filteredByBox');
        if (detections.isNotEmpty) {
          final top = detections.first;
          debugPrint('   🏆 highest risk candidate: ${top.tag} (${top.confidence.toStringAsFixed(3)})');
        }
      }

      return detections;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ YOLO ERROR: detection failed');
        debugPrint('❌ YOLO ERROR: $e');
        debugPrint('📋 STACK: $stack');
      }
      return const [];
    }
  }

  Future<void> dispose() async {
    if (kDebugMode) debugPrint('🗑️ YOLO: dispose() called');
    if (!isLoaded) return;

    try {
      await _vision.closeYoloModel();
      isLoaded = false;
      if (kDebugMode) debugPrint('✅ YOLO: model closed');
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ YOLO ERROR: failed to close model: $e');
        debugPrint('📋 STACK: $stack');
      }
    }
  }

  // ✅ שימושי לבדיקות וניטור
  Map<String, dynamic> getDebugInfo() => {
    'isLoaded': isLoaded,
    'thresholds': {
      'iou': _iouThreshold,
      'confidence': _confThreshold,
      'class': _classThreshold,
    },
    'allowedTagsCount': allowedTags.length,
  };
}