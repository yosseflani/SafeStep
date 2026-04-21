import 'package:camera/camera.dart';
// ספרייה לגישה למצלמה (CameraController, CameraImage וכו')

import 'package:permission_handler/permission_handler.dart';
// ספרייה לבקשת הרשאות מהמשתמש (מצלמה במקרה הזה)

class CameraService {
  // מחלקת Service שמנהלת את כל הלוגיקה של המצלמה (בלי UI)

  CameraController? _controller;
  // אובייקט שמנהל את המצלמה בפועל (יכול להיות null אם לא מאותחל)

  bool _isInitialized = false;
  // האם המצלמה כבר אותחלה

  bool _isProcessing = false;
  // מונע הצפת פריימים – אם עדיין מעבדים פריים, מדלגים על הבא

  CameraController? get controller => _controller;
  // מאפשר גישה ל-controller מבחוץ (למשל להצגת Preview)

  bool get isInitialized => _isInitialized;
  // מאפשר לבדוק מבחוץ אם המצלמה מוכנה

  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.low,
    // איכות המצלמה – נמוכה כדי לחסוך ביצועים (מספיק לזיהוי)
  }) async {

    if (_isInitialized) return;
    // אם כבר אותחל – לא מאתחל שוב

    try {
      // בקשת הרשאת מצלמה מהמשתמש
      final status = await Permission.camera.request();

      if (!status.isGranted) {
        throw Exception('Camera permission denied');
        // אם המשתמש לא אישר – זורקים שגיאה
      }

      final cameras = await availableCameras();
      // מביא את כל המצלמות במכשיר

      if (cameras.isEmpty) throw Exception('No cameras available');
      // אם אין מצלמות – שגיאה

      // מצלמה אחורית מועדפת, אם אין - לוקחים את הראשונה
      final selectedCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        // מחפש מצלמה אחורית
        orElse: () => cameras.first,
        // אם אין – לוקח את הראשונה
      );

      _controller = CameraController(
        selectedCamera,
        preset,
        enableAudio: false,
        // לא צריך מיקרופון

        imageFormatGroup: ImageFormatGroup.yuv420,
        // פורמט תמונה שמתאים לעיבוד (ML)
      );

      await _controller!.initialize();
      // מאתחל את המצלמה בפועל

      // הגדרות אופטימליות לאיכות זיהוי
      await _controller!.setFocusMode(FocusMode.auto);
      // פוקוס אוטומטי

      await _controller!.setExposureMode(ExposureMode.auto);
      // חשיפה אוטומטית

      await _controller!.setFlashMode(FlashMode.off);
      // מבטל פלאש

      _isInitialized = true;
      // מסמן שהמצלמה מוכנה

    } on CameraException catch (e) {
      _controller = null;
      // במקרה של שגיאת מצלמה – מאפס

      throw Exception('Camera error: ${e.description}');
      // זורק שגיאה עם פירוט

    } catch (e) {
      _controller = null;
      // שגיאה כללית – מאפס controller

      rethrow;
      // זורק את השגיאה הלאה
    }
  }

  // מתחיל הזרמת פריימים - כל פריים נשלח ל-onFrame
  Future<void> startStream(Future<void> Function(CameraImage image) onFrame) async {

    if (_controller == null || !_isInitialized) return;
    // אם אין מצלמה או לא אותחל – לא עושה כלום

    if (_controller!.value.isStreamingImages) return;
    // אם כבר זורם סטרים – לא מתחיל שוב

    await _controller!.startImageStream((CameraImage image) async {
      // מתחיל לקבל פריימים מהמצלמה

      if (_isProcessing) return;
      // אם עדיין מעבדים פריים קודם – מדלג

      _isProcessing = true;
      // מסמן שמתחיל עיבוד

      try {
        await onFrame(image);
        // שולח את הפריים לפונקציה שלך (למשל זיהוי אובייקטים)
      } finally {
        _isProcessing = false;
        // תמיד משתחרר (גם אם הייתה שגיאה)
      }
    });
  }

  // עוצר את הזרמת הפריימים
  Future<void> stopStream() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
      // עוצר את הסטרים אם הוא פועל
    }
  }

  // משחרר את כל המשאבים
  Future<void> dispose() async {
    await stopStream();
    // קודם עוצר סטרים

    await _controller?.dispose();
    // משחרר את המצלמה

    _controller = null;
    _isInitialized = false;
    _isProcessing = false;
    // מאפס את כל המשתנים
  }
}