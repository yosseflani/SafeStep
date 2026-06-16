import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {

  CameraController? _controller;
  bool _isInitialized = false;
  bool _isProcessing  = false;

  // ── ניטור ביצועים (Debug בלבד) ───────────────────────────
  int _frameCounter  = 0;
  int _skippedFrames = 0;
  static const _debugFrameInterval = 15; // דיווח כל 15 פריימים

  // ── Public getters ────────────────────────────────────────
  CameraController? get controller     => _controller;
  bool              get isInitialized  => _isInitialized;
  bool              get isStreaming     => _controller?.value.isStreamingImages == true;

  /// סטטיסטיקות ביצועים לשימוש חיצוני (UI / ניטור)
  Map<String, int> getStats() => {
    'total'     : _frameCounter,
    'skipped'   : _skippedFrames,
    'processed' : _frameCounter - _skippedFrames,
  };

  /// האם קצב הדילוג תקין (ברירת מחדל: עד 30%)
  bool isStreamHealthy({double maxSkipRate = 0.3}) {
    if (_frameCounter < _debugFrameInterval) return true;
    return (_skippedFrames / _frameCounter) <= maxSkipRate;
  }

  // ════════════════════════════════════════════════════════
  // INITIALIZE
  // ════════════════════════════════════════════════════════

  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.low,
  }) async {
    _debug('initialize() | preset=$preset');
    if (_isInitialized) return;

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) throw Exception('Camera permission denied');

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available');

      final selected = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        selected,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // אופטימלי ל-ML
      );

      await _controller!.initialize();

      // הגדרות אופטימליות לזיהוי
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setFlashMode(FlashMode.off);

      _isInitialized = true;
      _debug('✅ initialized successfully');

    } on CameraException catch (e) {
      _controller     = null;
      _isInitialized  = false;
      _debug('❌ CameraException: ${e.code} – ${e.description}');
      throw Exception('Camera error: ${e.description}');

    } catch (e) {
      _controller     = null;
      _isInitialized  = false;
      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════
  // STREAM
  // ════════════════════════════════════════════════════════

  Future<void> startStream(
      Future<void> Function(CameraImage image) onFrame,
      ) async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    _frameCounter  = 0;
    _skippedFrames = 0;

    await _controller!.startImageStream((CameraImage image) async {
      _frameCounter++;

      if (_isProcessing) {
        _skippedFrames++;

        if (kDebugMode && _frameCounter % _debugFrameInterval == 0) {
          final rate = (_skippedFrames / _frameCounter * 100).toStringAsFixed(1);
          _debug('frame=$_frameCounter | skipped=$_skippedFrames ($rate%)');
        }
        return;
      }

      _isProcessing = true;
      try {
        await onFrame(image);
      } catch (e, stack) {
        _debug('onFrame error: $e\n$stack');
      } finally {
        _isProcessing = false;
      }
    });

    _debug('🎬 stream started');
  }

  Future<void> stopStream() async {
    if (_controller?.value.isStreamingImages == true) {
      await _controller!.stopImageStream();
      _debug('🛑 stream stopped');
    }
  }

  // ════════════════════════════════════════════════════════
  // DISPOSE / RESET
  // ════════════════════════════════════════════════════════

  void resetStats() {
    _frameCounter  = 0;
    _skippedFrames = 0;
  }

  Future<void> dispose() async {
    _debug('dispose()');
    await stopStream();
    await _controller?.dispose();
    _controller     = null;
    _isInitialized  = false;
    _isProcessing   = false;
    resetStats();
  }

  // ════════════════════════════════════════════════════════
  // PRIVATE
  // ════════════════════════════════════════════════════════

  void _debug(String msg) {
    if (!kDebugMode) return;
    final t = DateTime.now().toIso8601String().split('T').last.split('.').first;
    debugPrint('[CameraService][$t] $msg');
  }
}