import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';
import '../models/detection.dart';

class YoloService {

  final FlutterVision _vision = FlutterVision();
  bool isLoaded = false;

  // ── ספי זיהוי ────────────────────────────────────────────
  // iou: סינון קופסאות כפולות – 0.4 מתאים לסביבה עירונית עמוסה
  // conf/class: 0.35 – פשרה בין רגישות למניעת התראות שווא
  // הסינון הסופי (50%) מתבצע ב-RiskScoringService
  static const double _iouThreshold   = 0.4;
  static const double _confThreshold  = 0.35;
  static const double _classThreshold = 0.35;

  // ── תגיות מותרות ─────────────────────────────────────────
  static const Set<String> allowedTags = {
    // רכבים ותחבורה
    'car', 'bus', 'truck', 'train', 'motorcycle', 'bicycle', 'scooter',
    // אנשים
    'person',
    // תשתית ותמרורים
    'traffic light', 'stop sign', 'crosswalk', 'fire hydrant', 'bench',
    // בעלי חיים
    'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
    'elephant', 'bear', 'zebra', 'giraffe',
    // חפצים אישיים
    'backpack', 'umbrella', 'handbag', 'suitcase',
    // ספורט ופנאי
    'skis', 'sports ball', 'skateboard', 'surfboard', 'tennis racket',
    // ריהוט
    'chair', 'couch', 'potted plant', 'bed', 'dining table',
    // אלקטרוניקה וכלים
    'vase', 'bottle', 'cup', 'book', 'cell phone', 'tv', 'laptop',
  };

  // ════════════════════════════════════════════════════════
  // INIT
  // ════════════════════════════════════════════════════════

  Future<void> initModel() async {
    _debug('initModel()');
    if (isLoaded) { _debug('already loaded – skipping'); return; }

    try {
      await _vision.loadYoloModel(
        labels     : 'assets/labels.txt',
        modelPath  : 'assets/yolov8n_float32.tflite',
        modelVersion: 'yolov8',
        numThreads : 2,
        useGpu     : false, // CPU יציב יותר על רוב מכשירי Android
      );

      isLoaded = true;
      _debug('✅ model loaded');
    } catch (e, stack) {
      isLoaded = false;
      _debug('❌ load failed: $e\n$stack');
      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════
  // DETECT
  // ════════════════════════════════════════════════════════

  Future<List<Detection>> detectObjects(
      List<Uint8List> bytesList,
      int imageHeight,
      int imageWidth, {
        double? confThreshold,
      }) async {
    if (!isLoaded || bytesList.isEmpty || imageHeight <= 0 || imageWidth <= 0) {
      _debug('invalid input or not loaded');
      return const [];
    }

    final activeConf = confThreshold ?? _confThreshold;

    try {
      final results = await _vision.yoloOnFrame(
        bytesList      : bytesList,
        imageHeight    : imageHeight,
        imageWidth     : imageWidth,
        iouThreshold   : _iouThreshold,
        confThreshold  : activeConf,
        classThreshold : _classThreshold,
      );

      final detections      = <Detection>[];
      int filteredByTag     = 0;
      int filteredByBox     = 0;
      int filteredByConf    = 0;

      for (final raw in results) {
        final tag    = (raw['tag'] ?? '').toString().trim().toLowerCase();
        final rawBox = (raw['box'] as List?) ?? const [];

        if (tag.isEmpty) continue;

        if (rawBox.length < 5) { filteredByBox++;  continue; }

        final confidence = (rawBox[4] as num).toDouble();
        if (confidence < activeConf) { filteredByConf++; continue; }

        if (!allowedTags.contains(tag)) { filteredByTag++; continue; }

        detections.add(Detection(
          tag       : tag,
          confidence: confidence,
          box       : [
            (rawBox[0] as num).toDouble(),
            (rawBox[1] as num).toDouble(),
            (rawBox[2] as num).toDouble(),
            (rawBox[3] as num).toDouble(),
          ],
        ));
      }

      if (kDebugMode && results.isNotEmpty) {
        _debug('raw=${results.length} accepted=${detections.length} '
            '(filtered: tag=$filteredByTag conf=$filteredByConf box=$filteredByBox)');
      }

      return detections;

    } catch (e, stack) {
      _debug('detection error: $e\n$stack');
      return const [];
    }
  }

  // ════════════════════════════════════════════════════════
  // DISPOSE
  // ════════════════════════════════════════════════════════

  Future<void> dispose() async {
    if (!isLoaded) return;
    try {
      await _vision.closeYoloModel();
      isLoaded = false;
      _debug('model closed');
    } catch (e, stack) {
      _debug('dispose error: $e\n$stack');
    }
  }

  // ════════════════════════════════════════════════════════
  // DEBUG INFO
  // ════════════════════════════════════════════════════════

  Map<String, dynamic> getDebugInfo() => {
    'isLoaded'        : isLoaded,
    'iouThreshold'    : _iouThreshold,
    'confThreshold'   : _confThreshold,
    'classThreshold'  : _classThreshold,
    'allowedTagsCount': allowedTags.length,
  };

  void _debug(String msg) {
    if (!kDebugMode) return;
    final t = DateTime.now().toIso8601String().split('T').last.split('.').first;
    debugPrint('[YoloService][$t] $msg');
  }
}