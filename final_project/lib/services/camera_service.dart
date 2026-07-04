import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/logger.dart';

/// שירות לניהול המצלמה והזרמת פריימים לזיהוי.
class CameraService {
  final _log = const AppLogger('CameraService');

  // בקר המצלמה הפעיל.
  CameraController? _controller;

  bool _isInitialized = false;
  bool _isProcessing = false;

  // נתוני ניטור ביצועים.
  int _frameCounter = 0;
  int _skippedFrames = 0;

  // תדירות דיווח במצב Debug.
  static const _debugFrameInterval = 15;

  CameraController? get controller => _controller;

  bool get isInitialized => _isInitialized;

  bool get isStreaming =>
      _controller?.value.isStreamingImages == true;

  /// מחזיר סטטיסטיקת עיבוד פריימים.
  Map<String, int> getStats() => {
    'total': _frameCounter,
    'skipped': _skippedFrames,
    'processed': _frameCounter - _skippedFrames,
  };

  /// בודק האם שיעור הדילוג על פריימים תקין.
  bool isStreamHealthy({double maxSkipRate = 0.3}) {
    if (_frameCounter < _debugFrameInterval) return true;

    return (_skippedFrames / _frameCounter) <= maxSkipRate;
  }

  /// מאתחל את המצלמה ובוחר מצלמה אחורית אם קיימת.
  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.low,
  }) async {
    _log.debug('initialize() | preset=$preset');

    if (_isInitialized) return;

    try {
      final status = await Permission.camera.request();

      if (!status.isGranted) {
        throw Exception('Camera permission denied');
      }

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // עדיפות למצלמה אחורית לזיהוי סביבתי.
      final selectedCamera = cameras.firstWhere(
            (camera) =>
        camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        selectedCamera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      // הגדרות בסיסיות לשיפור יציבות התמונה.
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setFlashMode(FlashMode.off);

      _isInitialized = true;

      _log.debug('Camera initialized successfully');
    } on CameraException catch (e) {
      _controller = null;
      _isInitialized = false;

      _log.debug('CameraException: ${e.code} - ${e.description}');

      throw Exception('Camera error: ${e.description}');
    } catch (_) {
      _controller = null;
      _isInitialized = false;

      rethrow;
    }
  }

  /// מתחיל הזרמת פריימים למנגנון הזיהוי.
  Future<void> startStream(
      Future<void> Function(CameraImage image) onFrame,
      ) async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    resetStats();

    await _controller!.startImageStream(
          (CameraImage image) async {
        _frameCounter++;

        // מונע עיבוד מקביל של כמה פריימים.
        if (_isProcessing) {
          _skippedFrames++;

          if (kDebugMode &&
              _frameCounter % _debugFrameInterval == 0) {
            final skippedRate =
            (_skippedFrames / _frameCounter * 100)
                .toStringAsFixed(1);

            _log.debug(
              'frame=$_frameCounter | '
                  'skipped=$_skippedFrames ($skippedRate%)',
            );
          }

          return;
        }

        _isProcessing = true;

        try {
          await onFrame(image);
        } catch (e, stack) {
          _log.debug('onFrame error: $e\n$stack');
        } finally {
          _isProcessing = false;
        }
      },
    );

    _log.debug('Camera stream started');
  }

  /// עוצר את הזרמת הפריימים.
  Future<void> stopStream() async {
    if (_controller?.value.isStreamingImages == true) {
      await _controller!.stopImageStream();
      _log.debug('Camera stream stopped');
    }
  }

  /// מאפס את נתוני הביצועים.
  void resetStats() {
    _frameCounter = 0;
    _skippedFrames = 0;
  }

  /// משחרר את משאבי המצלמה.
  Future<void> dispose() async {
    _log.debug('dispose()');

    await stopStream();
    await _controller?.dispose();

    _controller = null;
    _isInitialized = false;
    _isProcessing = false;

    resetStats();
  }

}