import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller; // מנהל את המצלמה
  bool _isInitialized = false; // האם מוכנה כבר

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;

  // מדליקה את המצלמה
  Future<void> initialize() async {
    final cameras = await availableCameras(); // מחזיר רשימה של כל המצלמות במכשיר
    if (cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    // בוחר מצלמה אחורית, אם אין לוקח את הראשונה ברשימה
    final CameraDescription selectedCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // יצירה של האובייקט שמנהל את המצלמה
    _controller = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    // אתחול ועכשיו מוכנה לשימוש
    await _controller!.initialize();
    _isInitialized = true;
  }

  //מתחיל הזרמת פריימים לפונקציה, כל פריים נשלח ל onFrame
  Future<void> startStream(Future<void> Function(CameraImage image) onFrame) async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    await _controller!.startImageStream((CameraImage image) async {
      await onFrame(image);
    });
  }

  // עוצרים כשלא צריך לזהות כלום (לפי הכפתור)
  Future<void> stopStream() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  // משחררים את המצלמה
  Future<void> dispose() async {
    await stopStream();
    await _controller?.dispose();
    _isInitialized = false;
  }
}