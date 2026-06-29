import 'package:camera/camera.dart'; // ייבוא ספריית camera של Flutter - מספקת CameraController, CameraImage וכו'

import 'package:flutter/foundation.dart'; // ייבוא ספריית foundation - כולל kDebugMode, debugPrint

import 'package:permission_handler/permission_handler.dart'; // ייבוא ספריית permission_handler - ניהול הרשאות באפליקציה

/// שירות האחראי על ניהול המצלמה והזרמת פריימים למערכת זיהוי המכשולים.
/// מחלקה שמנהלת את כל הלוגיקה של המצלמה: אתחול, הזרמת פריימים, וניטור ביצועים
class CameraService {

  /// בקר המצלמה הראשי.
  CameraController? _controller; // בקר המצלמה - nullable כי מתחיל כ-null עד שהמצלמה מאותחלת
  // ? = nullable type - יכול להיות null או CameraController

  /// מצב המצלמה ומצב עיבוד הפריימים.
  bool _isInitialized = false; // דגל שמציין אם המצלמה אותחלה בהצלחה
  bool _isProcessing = false; // דגל שמציין אם כרגע מעבדים פריים (מונע עיבוד מקבילי)

  /// נתוני ניטור ביצועים.
  int _frameCounter = 0; // מונה סך כל הפריימים שהתקבלו מהמצלמה
  int _skippedFrames = 0; // מונה הפריימים שדילגנו עליהם (כי עדיין מעבדים פריים קודם)

  /// תדירות דיווח במצב פיתוח.
  static const _debugFrameInterval = 15; // כל 15 פריימים מדפיסים סטטיסטיקות ב-debug

  /// גישה לבקר המצלמה לצורך תצוגה במסכים.
  CameraController? get controller => _controller; // getter - מאפשר לקרוא את _controller מחוץ למחלקה
  // => = arrow function - קיצור לפונקציה שמחזירה ערך

  /// מציין האם המצלמה מוכנה לשימוש.
  bool get isInitialized => _isInitialized; // getter - מחזיר את מצב האתחול

  /// מציין האם הזרמת פריימים פעילה.
  bool get isStreaming => // getter - בודק אם המצלמה מזרימה פריימים כרגע
  _controller?.value.isStreamingImages == true; // ?. = null-aware operator - אם _controller null, כל הביטוי null
  // .value = מידע על מצב המצלמה
  // .isStreamingImages = האם המצלמה מזרימה פריימים
  // == true = בדיקה שהערך הוא true (לא null)

  /// מחזיר נתוני ביצועים בסיסיים.
  Map<String, int> getStats() => { // getter שמחזיר Map עם סטטיסטיקות
    'total': _frameCounter, // סך כל הפריימים
    'skipped': _skippedFrames, // פריימים שדילגנו עליהם
    'processed': _frameCounter - _skippedFrames, // פריימים שעובדו בפועל
  };

  /// בודק האם שיעור הדילוג על פריימים תקין.
  bool isStreamHealthy({double maxSkipRate = 0.3}) { // פרמטר אופציונלי: מקסימום 30% דילוגים
    if (_frameCounter < _debugFrameInterval) return true; // אם אין מספיק נתונים - נחשב תקין

    return (_skippedFrames / _frameCounter) <= maxSkipRate; // בדיקה שאחוז הדילוגים <= 30%
    // _skippedFrames / _frameCounter = יחס הדילוגים (0 עד 1)
    // <= maxSkipRate = צריך להיות קטן או שווה ל-0.3 (30%)
  }

  /// אתחול המצלמה ובחירת מצלמה אחורית לזיהוי מכשולים.
  Future<void> initialize({ // פונקציה אסינכרונית שמאתחלת את המצלמה
    ResolutionPreset preset = ResolutionPreset.low, // פרמטר אופציונלי: רזולוציית המצלמה (ברירת מחדל: נמוכה)
  }) async {
    _debug('initialize() | preset=$preset'); // הדפסת הודעת debug

    if (_isInitialized) return; // אם המצלמה כבר מאותחלת - יציאה (מונע אתחול כפול)

    try { // בלוק try-catch לטיפול בשגיאות
      // בקשת הרשאת מצלמה.
      final status = await Permission.camera.request(); // בקשת הרשאה למצלמה מהמשתמש
      // await - ממתין שהמשתמש יאשר/ידחה
      // status = מצב ההרשאה (granted, denied, permanentlyDenied וכו')

      if (!status.isGranted) { // בדיקה אם ההרשאה ניתנה
        throw Exception('Camera permission denied'); // זריקת חריגה אם לא
      }

      // קבלת רשימת המצלמות במכשיר.
      final cameras = await availableCameras(); // קבלת רשימת כל המצלמות הזמינות במכשיר
      // בדרך כלל: מצלמה קדמית ואחורית

      if (cameras.isEmpty) { // בדיקה שיש מצלמות
        throw Exception('No cameras available'); // זריקת חריגה אם אין מצלמות
      }

      // העדפת מצלמה אחורית לצורך זיהוי הסביבה.
      final selectedCamera = cameras.firstWhere( // מציאת המצלמה המתאימה ביותר
            (camera) => // פונקציה שבודקת כל מצלמה
        camera.lensDirection == CameraLensDirection.back, // בודק אם זו מצלמה אחורית
        orElse: () => cameras.first, // אם לא נמצאה מצלמה אחורית - השתמש בראשונה ברשימה
      );

      // יצירת בקר מצלמה בפורמט מתאים לעיבוד תמונה.
      _controller = CameraController( // יצירת בקר מצלמה חדש
        selectedCamera, // המצלמה שנבחרה
        preset, // רזולוציה (low = מהיר יותר, high = איכותי יותר)
        enableAudio: false, // לא מקליט אודיו (רק וידאו)
        imageFormatGroup: ImageFormatGroup.yuv420, // פורמט תמונה YUV420 - מתאים לעיבוד במודלי AI
      );

      await _controller!.initialize(); // אתחול הבקר - ממתין שהמצלמה תהיה מוכנה
      // ! = force unwrap - אנחנו בטוחים ש-_controller לא null (יצרנו אותו בשורה הקודמת)

      // אופטימיזציה לאיכות זיהוי.
      await _controller!.setFocusMode(FocusMode.auto); // הגדרת פוקוס אוטומטי
      await _controller!.setExposureMode(ExposureMode.auto); // הגדרת חשיפה אוטומטית
      await _controller!.setFlashMode(FlashMode.off); // כיבוי הפלאש (לא נדרש לזיהוי)

      _isInitialized = true; // עדכון הדגל שהמצלמה אותחלה בהצלחה

      _debug('Camera initialized successfully'); // הדפסת הודעת הצלחה
    } on CameraException catch (e) { // תפיסת שגיאות ספציפיות של המצלמה
      _controller = null; // איפוס הבקר
      _isInitialized = false; // עדכון הדגל שהאתחול נכשל

      _debug('CameraException: ${e.code} - ${e.description}'); // הדפסת פרטי השגיאה

      throw Exception('Camera error: ${e.description}'); // זריקת חריגה חדשה עם תיאור ברור
    } catch (_) { // תפיסת כל שאר השגיאות
      _controller = null; // איפוס הבקר
      _isInitialized = false; // עדכון הדגל

      rethrow; // זריקת השגיאה המקורית הלאה
    }
  }

  /// מתחיל הזרמת פריימים למנוע הזיהוי.
  Future<void> startStream( // פונקציה שמתחילה את הזרמת הפריימים
      Future<void> Function(CameraImage image) onFrame, // callback - פונקציה שנקראת עם כל פריים חדש
      ) async {
    if (_controller == null || !_isInitialized) return; // בדיקה שהמצלמה מאותחלת
    if (_controller!.value.isStreamingImages) return; // בדיקה שכבר לא מזרימים (למנוע הזרמה כפולה)

    resetStats(); // איפוס מוני הסטטיסטיקה

    await _controller!.startImageStream( // התחלת הזרמת פריימים מהמצלמה
          (CameraImage image) async { // פונקציה שנקראת עם כל פריים חדש
        _frameCounter++; // הגדלת מונה הפריימים הכולל

        // מניעת עיבוד מספר פריימים במקביל.
        if (_isProcessing) { // אם עדיין מעבדים פריים קודם
          _skippedFrames++; // הגדלת מונה הדילוגים

          if (kDebugMode && // אם במצב debug
              _frameCounter % _debugFrameInterval == 0) { // וכל 15 פריימים
            final skippedRate = // חישוב אחוז הדילוגים
            (_skippedFrames / _frameCounter * 100) // (דילוגים / סך הכל * 100)
                .toStringAsFixed(1); // עיגול לספרה אחת אחרי הנקודה

            _debug( // הדפסת סטטיסטיקות
              'frame=$_frameCounter | ' // מספר פריים
                  'skipped=$_skippedFrames ($skippedRate%)', // דילוגים ואחוז
            );
          }

          return; // יציאה מהפונקציה - לא מעבדים את הפריים הזה
        }

        _isProcessing = true; // סימון שאנחנו מעבדים פריים

        try { // בלוק try-catch לטיפול בשגיאות בעיבוד
          // העברת הפריים למנגנון הזיהוי.
          await onFrame(image); // קריאה ל-callback עם הפריים
          // await - ממתין שהעיבוד יסתיים (יכול לקחת זמן)
        } catch (e, stack) { // תפיסת שגיאות
          _debug('onFrame error: $e\n$stack'); // הדפסת פרטי השגיאה
        } finally { // בלוק finally - תמיד רץ, גם אם יש שגיאה
          _isProcessing = false; // סימון שסיימנו לעבד את הפריים
        }
      },
    );

    _debug('Camera stream started'); // הדפסת הודעה שההזרמה התחילה
  }

  /// עוצר את הזרמת הפריימים.
  Future<void> stopStream() async { // פונקציה שעוצרת את הזרמת הפריימים
    if (_controller?.value.isStreamingImages == true) { // בדיקה שהמצלמה מזרימה כרגע
      await _controller!.stopImageStream(); // עצירת ההזרמה
      _debug('Camera stream stopped'); // הדפסת הודעה
    }
  }

  /// מאפס נתוני ניטור ביצועים.
  void resetStats() { // איפוס כל המונים
    _frameCounter = 0; // איפוס מונה פריימים כולל
    _skippedFrames = 0; // איפוס מונה דילוגים
  }

  /// שחרור משאבי המצלמה בעת סגירת המסך.
  Future<void> dispose() async { // פונקציה שמשחררת את כל המשאבים
    _debug('dispose()'); // הדפסת הודעה

    await stopStream(); // עצירת הזרמת פריימים
    await _controller?.dispose(); // שחרור משאבי המצלמה (זיכרון, חיישנים וכו')

    _controller = null; // איפוס הבקר
    _isInitialized = false; // עדכון דגל אתחול
    _isProcessing = false; // עדכון דגל עיבוד

    resetStats(); // איפוס סטטיסטיקות
  }

  /// הדפסת הודעות פיתוח בלבד.
  void _debug(String message) { // פונקציה פרטית להדפסת debug
    if (!kDebugMode) return; // אם לא במצב debug - יציאה

    final time = DateTime.now() // קבלת הזמן הנוכחי
        .toIso8601String() // המרה לפורמט ISO 8601
        .split('T') // פיצול לפי T
        .last // לקיחת השעה
        .split('.') // פיצול לפי נקודה
        .first; // לקיחת שעה ללא מילישניות

    debugPrint('[CameraService][$time] $message'); // הדפסה בפורמט: [שם השירות][שעה] הודעה
  }
}