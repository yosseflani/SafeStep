import 'dart:typed_data';
import 'package:flutter_vision/flutter_vision.dart';
import '../models/detection.dart';

class YoloService {
  late final FlutterVision _vision;
  bool isLoaded = false;

  YoloService() {
    _vision = FlutterVision();
  }

  // טוען את המודל
  Future<void> initModel() async {
    await _vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/yolov8n_float32.tflite',
      modelVersion: 'yolov8',
      numThreads: 2,
      useGpu: true,
    );
    isLoaded = true;
  }

  // הפונקציה שמקבלת תמונה ומחזירה זיהויים
  Future<List<Detection>> detectObjects(
      List<Uint8List> bytesList,
      int imageHeight,
      int imageWidth,
      ) async {
    if (!isLoaded) return const [];

    final results = await _vision.yoloOnFrame(
      bytesList: bytesList,
      imageHeight: imageHeight,
      imageWidth: imageWidth,
      iouThreshold: 0.4,
      confThreshold: 0.5,
      classThreshold: 0.2,
    );

    // יוצר רשימה של הזיהויים
    final List<Detection> detections = [];

    // עובר בלולאה זיהוי זיהוי
    for (final raw in results) {
      final tag = (raw['tag'] ?? '').toString();
      final rawBox = (raw['box'] as List?) ?? const [];

      if (tag.isEmpty || rawBox.length < 5) continue;

      final box = rawBox.map((e) => (e as num).toDouble()).toList();
      final confidence = box[4];

      if (confidence < 0.5) continue;

      // יוצר את האובייקט detection
      detections.add(
        Detection(
          tag: tag,
          confidence: confidence,
          box: box,
        ),
      );
    }

    return detections;
  }

  // סוגר את המודל ומשחרר זיכרון
  Future<void> dispose() async {
    if (!isLoaded) return;
    await _vision.closeYoloModel();
    isLoaded = false;
  }
}