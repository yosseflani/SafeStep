import 'dart:typed_data';
// מאפשר עבודה עם נתוני תמונה בינאריים (bytes מהמצלמה)

import 'package:flutter/foundation.dart';
// מאפשר debugPrint ו-kDebugMode

import 'package:flutter_vision/flutter_vision.dart';
// ספרייה להרצת מודל YOLO (זיהוי אובייקטים)

import '../models/detection.dart';
// מודל Detection שאתה משתמש בו לתוצאות

class YoloService {
  // מחלקה שמנהלת את מודל הזיהוי (YOLO)

  late final FlutterVision _vision = FlutterVision();
  // אובייקט שמריץ את המודל

  bool isLoaded = false;
  // האם המודל כבר נטען

  // ספים לזיהוי (אפשר לכוון ביצועים/דיוק)
  static const double _iouThreshold = 0.5;
  // חפיפה בין קופסאות (לסינון כפילויות)

  static const double _confThreshold = 0.5;
  // ביטחון מינימלי לזיהוי

  static const double _classThreshold = 0.5;
  // סף לסיווג

  // רשימת האובייקטים שהאפליקציה תזהה
  static const Set<String> allowedTags = {
    'person', 'bicycle', 'car', 'motorcycle', 'bus', 'train', 'truck',
    'traffic light', 'fire hydrant', 'stop sign', 'bench', 'bird', 'cat',
    'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe',
    'backpack', 'umbrella', 'handbag', 'suitcase', 'skis', 'sports ball',
    'skateboard', 'surfboard', 'tennis racket', 'chair', 'couch',
    'potted plant', 'bed', 'dining table',
  };

  // טוען את מודל YOLO מהקבצים
  Future<void> initModel() async {
    if (isLoaded) return;
    // אם כבר נטען → לא טוען שוב

    try {
      await _vision.loadYoloModel(
        labels: 'assets/labels.txt',
        // קובץ שמכיל שמות של אובייקטים

        modelPath: 'assets/yolov8n_float32.tflite',
        // המודל עצמו

        modelVersion: 'yolov8',
        // גרסת YOLO

        numThreads: 2,
        // מספר threads (ביצועים)

        useGpu: true,
        // שימוש ב-GPU אם יש (מהיר יותר)
      );

      isLoaded = true;
      // מסמן שהמודל מוכן

    } catch (e) {
      isLoaded = false;
      // אם נכשל → לא נטען

      rethrow;
      // זורק שגיאה הלאה
    }
  }

  // מקבל פריים ומחזיר רשימת זיהויים
  Future<List<Detection>> detectObjects(
      List<Uint8List> bytesList,
      int imageHeight,
      int imageWidth, {
        double? confThreshold,
        // אפשרות לשנות רגישות מבחוץ
      }) async {

    if (!isLoaded) return const [];
    // אם המודל לא נטען → מחזיר ריק

    // בדיקות תקינות לקלט
    if (bytesList.isEmpty || imageHeight <= 0 || imageWidth <= 0) {
      if (kDebugMode) debugPrint('YOLO: Invalid input to detectObjects');
      return const [];
    }

    try {
      final results = await _vision.yoloOnFrame(
        bytesList: bytesList,
        // נתוני התמונה

        imageHeight: imageHeight,
        imageWidth: imageWidth,

        iouThreshold: _iouThreshold,
        // סינון חפיפות

        confThreshold: confThreshold ?? _confThreshold,
        // ביטחון מינימלי

        classThreshold: _classThreshold,
      );

      if (kDebugMode && results.isNotEmpty) {
        debugPrint('YOLO: ${results.length} raw detections');
      }

      final detections = <Detection>[];
      // רשימה סופית של זיהויים

      for (final raw in results) {
        // עובר על כל תוצאה מהמודל

        final tag = (raw['tag'] ?? '').toString().trim().toLowerCase();
        // שם האובייקט

        final rawBox = (raw['box'] as List?) ?? const [];
        // קואורדינטות

        if (tag.isEmpty || rawBox.length < 5) continue;
        // אם אין מידע → מדלג

        if (!allowedTags.contains(tag)) continue;
        // אם האובייקט לא מעניין → מדלג

        final confidence = (rawBox[4] as num).toDouble();
        // רמת ביטחון

        if (confidence < _confThreshold) continue;
        // אם ביטחון נמוך → מדלג

        // לוקח רק 4 ערכי מיקום
        final box = [
          (rawBox[0] as num).toDouble(),
          (rawBox[1] as num).toDouble(),
          (rawBox[2] as num).toDouble(),
          (rawBox[3] as num).toDouble(),
        ];

        detections.add(
          Detection(tag: tag, confidence: confidence, box: box),
          // יוצר אובייקט Detection
        );
      }

      return detections;
      // מחזיר רשימת זיהויים

    } catch (e, stack) {
      if (kDebugMode) debugPrint('YOLO error: $e\n$stack');
      return const [];
      // אם יש שגיאה → לא מפיל את האפליקציה
    }
  }

  // משחרר את המודל מהזיכרון
  Future<void> dispose() async {
    if (!isLoaded) return;

    await _vision.closeYoloModel();
    // סוגר את המודל

    isLoaded = false;
  }
}