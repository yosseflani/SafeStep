import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;

  bool _isInitialized = false;
  bool _isProcessing = false;

  // ✅ מעקב ביצועים – מופעל רק ב-Debug כדי לא לפגוע ב-Release
  int _frameCounter = 0;
  int _skippedFrames = 0;
  static const _debugFrameInterval = 15; // דווח כל 15 פריימים

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;

  // ✅ חשיפת סטטיסטיקות לשימוש חיצוני (לניטור באפליקציה)
  Map<String, int> getStats() => {
    'total': _frameCounter,
    'skipped': _skippedFrames,
    'processed': _frameCounter - _skippedFrames,
  };

  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.low,
  }) async {
    if (kDebugMode) debugPrint('📷 CAMERA: initialize() | preset=$preset');

    if (_isInitialized) return;

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) throw Exception('Camera permission denied');

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available');

      final selectedCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        selectedCamera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // ✅ פורמט אופטימלי ל-ML
      );

      await _controller!.initialize();

      // ✅ הגדרות אופטימליות לזיהוי
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setFlashMode(FlashMode.off);

      _isInitialized = true;
      if (kDebugMode) debugPrint('✅ CAMERA: initialized successfully');
    } on CameraException catch (e) {
      _controller = null;
      _isInitialized = false;
      if (kDebugMode) debugPrint('❌ CAMERA ERROR: ${e.code} - ${e.description}');
      throw Exception('Camera error: ${e.description}');
    } catch (e) {
      _controller = null;
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> startStream(
      Future<void> Function(CameraImage image) onFrame,
      ) async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    _frameCounter = 0;
    _skippedFrames = 0;

    await _controller!.startImageStream((CameraImage image) async {
      _frameCounter++;

      // ✅ לוגיקת דילוג חכמה עם ניטור
      if (_isProcessing) {
        _skippedFrames++;

        // ✅ דווח תקופתי רק ב-Debug
        if (kDebugMode && _frameCounter % _debugFrameInterval == 0) {
          final dropRate = (_skippedFrames / _frameCounter * 100).toStringAsFixed(1);
          debugPrint('📊 CAMERA: frame=$_frameCounter | skipped=$_skippedFrames ($dropRate%) | isProcessing=$_isProcessing');
        }
        return;
      }

      _isProcessing = true;

      try {
        await onFrame(image);
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint('❌ CAMERA: onFrame failed: $e');
          debugPrint('STACK: $stack');
        }
      } finally {
        _isProcessing = false;
      }
    });

    if (kDebugMode) debugPrint('🎬 CAMERA: stream started');
  }

  // ✅ מתודה חדשה: בדיקת בריאות הסטרים
  bool isStreamHealthy({double maxSkipRate = 0.3}) {
    if (_frameCounter < _debugFrameInterval) return true;
    final skipRate = _skippedFrames / _frameCounter;
    return skipRate <= maxSkipRate;
  }

  // ✅ מתודה חדשה: איפוס סטטיסטיקות (לניטור תקופתי)
  void resetStats() {
    _frameCounter = 0;
    _skippedFrames = 0;
  }

  Future<void> stopStream() async {
    if (_controller?.value.isStreamingImages == true) {
      await _controller!.stopImageStream();
      if (kDebugMode) debugPrint('🛑 CAMERA: stream stopped');
    }
  }

  Future<void> dispose() async {
    if (kDebugMode) debugPrint('🗑️ CAMERA: dispose()');

    await stopStream();
    await _controller?.dispose();

    _controller = null;
    _isInitialized = false;
    _isProcessing = false;
    resetStats();
  }
}