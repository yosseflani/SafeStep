import 'package:camera/camera.dart'; // ספריית מצלמה – מאפשרת עבודה עם CameraImage, שליטה במצלמה וכו'
import 'package:flutter/foundation.dart'; // כלים בסיסיים של Flutter (כמו kDebugMode)
import 'package:flutter/material.dart'; // רכיבי UI של Flutter (כפתורים, טקסטים, צבעים וכו')
import 'package:flutter_tts/flutter_tts.dart'; // ספריית Text To Speech – דיבור בקול
import 'package:flutter_beep/flutter_beep.dart'; // ספריית צפצוף – מייצרת צליל התראה מובנה
import 'package:vibration/vibration.dart'; // ספריית רטט – מאפשרת להפעיל vibration במכשיר
import 'dart:math'; // לחישוב sqrt עבור האקסלרומטר
import 'dart:async'; // לניהול StreamSubscription של האקסלרומטר
import 'package:sensors_plus/sensors_plus.dart'; // ספריית חיישנים – קריאת נתוני האקסלרומטר

import '../models/detection.dart'; // מודל שמייצג אובייקט שזוהה (Detection)
import '../services/alert_service.dart'; // שירות שמנהל התראות קוליות
import '../services/camera_service.dart'; // שירות שמנהל את המצלמה
import '../services/cooldown_manager.dart'; // מנהל זמן בין התראות (כדי לא להציף)
import '../services/risk_scoring_service.dart'; // שירות שמחשב רמת סיכון
import '../services/yolo_service.dart'; // שירות שמריץ את מודל YOLO לזיהוי אובייקטים
import '../services/voice_command_service.dart'; // ייבוא שירות שמטפל בזיהוי פקודות קוליות (Speech-to-Text)
import 'display_manager.dart'; // ייבוא המחלקה DisplayManager שאחראית על לוגיקת זמן התצוגה והחלטה מתי לעדכן
import 'settings_screen.dart'; // מסך ההגדרות

class MainScreen extends StatefulWidget { // Widget עם State (משתנה בזמן ריצה)
  const MainScreen({super.key}); // בנאי – מקבל key ומעביר ל־super

  @override
  State<MainScreen> createState() => _MainScreenState(); // יוצר את ה־State של המסך
}

const Color primaryColor = Color(0xFFFF7A00); // צבע ראשי קבוע (כתום)

class _MainScreenState extends State<MainScreen> {
  // מחלקת ה־State שמכילה את כל הלוגיקה

  final CameraService _cameraService = CameraService(); // שירות מצלמה
  final YoloService _yoloService = YoloService(); // שירות זיהוי YOLO
  final RiskScoringService _riskScoringService = RiskScoringService(); // חישוב סיכון
  final CooldownManager _cooldownManager = CooldownManager(); // מניעת התראות חוזרות מהר
  final AlertService _alertService = AlertService(); // שירות התראות קוליות
  final FlutterTts _tts = FlutterTts(); // מנוע Text To Speech
  final DisplayManager _displayManager = DisplayManager(); // יצירת מופע של DisplayManager כדי להשתמש בו בתוך המסך
  final VoiceCommandService _voiceService = VoiceCommandService(); // יצירת מופע של שירות הפקודות הקוליות

  // ------------------- רטט -------------------
  DateTime? _lastVibrationTime; // זמן הרטט האחרון
  static const _vibrationCooldown = Duration(milliseconds: 500); // זמן מינימלי בין רטטים

  // ------------------- אקסלרומטר -------------------
  StreamSubscription? _accelerometerSubscription; // מנוי לאירועי האקסלרומטר – נשמר כדי לאפשר ביטול ב-dispose
  static const _movementThreshold = 1.2; // סף תנועה: נמוך = רגיש יותר, גבוה = רק תנועה חזקה
  final List<double> _magnitudeHistory = []; // רשימת 10 המדידות האחרונות לצורך ממוצע נע
  static const _historySize = 10; // כמות המדידות לשמור בהיסטוריה

  // ------------------- מצב מערכת -------------------
  bool _isInitialized = false; // האם המערכת כבר אותחלה
  bool _isRunning = false; // האם הזיהוי כרגע פועל
  bool _userIsMoving = false; // האם המשתמש זז כרגע (משפיע על סף ההתראות)

  // ------------------- הגדרות -------------------
  double _speechRate = 0.5; // מהירות דיבור
  bool _vibrationEnabled = true; // האם רטט פעיל
  String _language = 'he-IL'; // שפה (עברית)
  String? _selectedVoice; // קול נבחר (יכול להיות null)
  List<Map<String, dynamic>> _voices = []; // רשימת קולות זמינים

  Detection? _currentMostDangerous; // האובייקט הכי מסוכן כרגע (או null)

  bool get _isHebrew => _language.startsWith('he');
  // האם השפה הנוכחית היא עברית

  // ------------------- ספי התראה -------------------
  // מתחת ל-30: שקט לגמרי
  // 30–40: רטט בלבד
  // 40–65: רטט + שם האובייקט בקול
  // מעל 65: רטט + צפצוף + שם האובייקט בקול
  static const _vibrationOnlyThreshold = 30.0; // סף רטט בלבד
  static const _voiceAlertThreshold = 40.0; // סף הוספת התראה קולית
  static const _beepAlertThreshold = 65.0; // סף הוספת צפצוף לפני ההתראה

  @override
  void initState() {
    // פונקציה שנקראת פעם אחת כשהמסך נוצר
    super.initState(); // קריאה ל־initState של המחלקה האב
    _initializeSystem(); // אתחול המערכת (מצלמה, מודל וכו')
  }

  Future<void> _initializeSystem() async {
    // פונקציה אסינכרונית שמבצעת אתחול של כל המערכת
    try {
      final results = await Future.wait([
        // מריץ כמה פעולות אסינכרוניות במקביל ומחכה שכולן יסתיימו
        _cameraService.initialize(), // אתחול המצלמה
        _yoloService.initModel(), // טעינת מודל YOLO לזיהוי אובייקטים
        _voiceService.initialize(), // אתחול שירות זיהוי הקול
        _alertService.initialize( // אתחול שירות ההתראות הקוליות
          language: _language,
          speechRate: _speechRate,
          voiceAlertsEnabled: true,
        ),
      ]);

      final bool voiceAvailable = results[2] as bool;
      // בודק האם זיהוי קול זמין במכשיר

      if (kDebugMode) {
        debugPrint('Voice available: $voiceAvailable');
      }

      final controller = _cameraService.controller;
      // מביא את ה-controller של המצלמה

      if (controller?.value.previewSize != null) {
        // בדיקה שהמצלמה מאותחלת ויש גודל תצוגה
        _riskScoringService.updateResolution(
          controller!.value.previewSize!.width.toInt(),
          controller.value.previewSize!.height.toInt(),
        );
        // מעדכן את שירות חישוב הסיכון ברזולוציה האמיתית של המצלמה
      }

      final raw = await _tts.getVoices ?? [];
      // מביא רשימת קולות מה-TTS (אם null אז רשימה ריקה)

      _voices = raw.whereType<Map<String, dynamic>>().toList();
      // מסנן רק איברים שהם Map<String, dynamic> והופך לרשימה

      await _applyTtsSettings();
      // מיישם את הגדרות ה-TTS (שפה, קול וכו')

      if (!mounted) return;
      // אם ה-Widget כבר לא קיים בעץ – לא ממשיכים

      setState(() => _isInitialized = true);
      // מעדכן את ה-state: המערכת מוכנה

      // התחלת האזנה לאקסלרומטר לזיהוי תנועת המשתמש
      _accelerometerSubscription = accelerometerEvents.listen((event) {
        final magnitude = sqrt(
          event.x * event.x +
              event.y * event.y +
              event.z * event.z,
        );
        // מחשב את עוצמת התנועה הכוללת בשלושת הצירים
        // כשהטלפון נייח התוצאה היא ~9.8 (כוח הכבידה בלבד)

        _magnitudeHistory.add((magnitude - 9.8).abs());
        // מוסיף את הסטייה מכוח הכבידה להיסטוריה

        if (_magnitudeHistory.length > _historySize) {
          _magnitudeHistory.removeAt(0);
          // שומר רק את 10 המדידות האחרונות
        }

        final average = _magnitudeHistory.reduce((a, b) => a + b)
            / _magnitudeHistory.length;
        // מחשב ממוצע נע של הסטיות – מונע קפיצות שקריות בין עמידה להליכה

        final moving = average > _movementThreshold;
        // רק אם הממוצע עובר את הסף נחשב שהמשתמש בתנועה

        if (moving != _userIsMoving) {
          setState(() => _userIsMoving = moving);
          // מעדכן את ה-state רק אם המצב השתנה (חיסכון ב-rebuilds)
        }
      });

      await _resumeListening();
      // התחלת האזנה לפקודות קוליות

    } catch (e, stack) {
      if (kDebugMode) debugPrint('Init error: $e\n$stack');
      // הדפסה לקונסול רק במצב debug

      if (!mounted) return;

      setState(() {});
      // גורם ל-rebuild גם בלי שינוי ערכים

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isHebrew ? 'שגיאה באתחול המערכת' : 'System initialization error',
          ),
          backgroundColor: Colors.red.shade900,
          action: SnackBarAction(
            label: _isHebrew ? 'נסה שוב' : 'Retry',
            textColor: Colors.white,
            onPressed: _initializeSystem,
            // לחיצה מפעילה שוב את האתחול
          ),
        ),
      );
    }
  }

  Future<void> _applyTtsSettings() async {
    // פונקציה אסינכרונית שמחילה את הגדרות הקול
    try {
      await _tts.setLanguage(_language);
      // מגדיר את שפת הדיבור במנוע ה-TTS

      await _tts.setSpeechRate(_speechRate.clamp(0.1, 2.0));
      // מגדיר את מהירות הדיבור עם הגבלה לטווח תקין

      if (_selectedVoice != null) {
        await _tts.setVoice({'name': _selectedVoice!});
        // מגדיר את הקול הנבחר במנוע ה-TTS
      }

      await _alertService.updateSettings(
        language: _language,
        speechRate: _speechRate,
        voiceAlertsEnabled: true,
      );
      // מעדכן גם את שירות ההתראות עם אותן הגדרות

    } catch (e) {
      if (kDebugMode) debugPrint('TTS settings error: $e');
      // מדפיס את השגיאה רק במצב debug
    }
  }

  Future<void> _resumeListening() async {
    if (!mounted) return;
    if (_voiceService.isListening) return;

    while (_alertService.isSpeaking) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
    }
    // חכה שה-TTS יסיים לגמרי לפני שמאזינים לפקודות קוליות

    await _voiceService.startListening(
      _handleVoiceCommand,
      localeId: _isHebrew ? 'iw_IL' : 'en_US',
      // שפת זיהוי הקול לפי הגדרת המשתמש

      onError: () async {
        // אחרי כל שגיאה מתחילים מחדש אוטומטית
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 500));
        await _resumeListening();
      },
    );
  }

  Future<void> _startDetection() async {
    // פונקציה שמתחילה את תהליך הזיהוי
    if (!_isInitialized || _isRunning) return;
    // אם המערכת לא אותחלה או שכבר פועלת - לא ממשיכים

    await _alertService.speakSystemStarted();
    // משמיע הודעה שהמערכת התחילה

    if (_vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
      Vibration.vibrate(duration: 100);
      // מרטיט לזמן קצר כסימן להתחלה
    }

    setState(() => _isRunning = true);
    // מעדכן שהמערכת כרגע רצה

    await _cameraService.startStream((CameraImage image) async {
      // מתחיל stream מהמצלמה; כל פריים נכנס לכאן

      final detections = await _yoloService.detectObjects(
        image.planes.map((plane) => plane.bytes).toList(),
        image.height,
        image.width,
      );
      // שולח את הפריים למודל הזיהוי

      _riskScoringService.updateResolution(image.width, image.height);
      // מעדכן את הרזולוציה לשירות הסיכון

      final scored = _riskScoringService.scoreDetections(detections);
      // מחשב ניקוד סיכון לכל זיהוי

      final top = scored.isNotEmpty ? scored.first : null;
      // בוחר את האובייקט הכי מסוכן, או null אם אין

      if (!mounted) return;
      // אם המסך כבר לא קיים - עוצרים

      final shouldUpdateDisplay = _displayManager.shouldUpdateDisplay(
        hasCurrentObject: _currentMostDangerous != null,
        newRisk: top?.riskScore,
        currentRisk: _currentMostDangerous?.riskScore,
      );
      // בודק האם לעדכן את התצוגה לפי לוגיקת זמן מינימלי

      if (shouldUpdateDisplay) {
        setState(() {
          _currentMostDangerous = top;
          // שומר את האובייקט הכי מסוכן החדש

          if (top != null) {
            _displayManager.markDisplayStart();
            // מסמן התחלת זמן תצוגה חדש
          } else {
            _displayManager.clearDisplayStart();
            // מאפס אם אין אובייקט
          }
        });
      }

      if (top == null) return;
      // אין אובייקט → אין מה לבדוק

      final alertLevel = _getAlertLevel(top);
      // בודק איזו רמת התראה מתאימה לציון הסיכון

      if (alertLevel == _AlertLevel.none) return;
      // מתחת לסף המינימלי → שקט לגמרי

      if (!_cooldownManager.canAlert(top.tag)) return;
      // עדיין בזמן המתנה עבור אובייקט זה → לא מתריעים שוב

      _cooldownManager.markAlerted(top.tag);
      // מסמן שכבר התרענו על התג הזה

      await _handleVibration(top.tag);
      // מפעיל רטט לפי סוג האובייקט (קיים בכל הרמות מעל none)

      if (alertLevel == _AlertLevel.vibrationOnly) return;
      // רמת רטט בלבד → לא מדברים

      // רמת קול: עוצרים האזנה לפני שמדברים
      await _voiceService.stopListening();
      // חשוב כדי למנוע מצב שהאפליקציה שומעת את עצמה

      if (alertLevel == _AlertLevel.beepAndVoice) {
        await FlutterBeep.beep();
        // צפצוף לפני ההכרזה – מתריע שמדובר בסכנה גבוהה
        await Future.delayed(const Duration(milliseconds: 300));
        // המתנה קצרה בין הצפצוף להכרזה הקולית
      }

      final currentRisk = _currentMostDangerous?.riskScore;
      // שומר את רמת הסיכון הנוכחית לפני ההשמעה

      await _alertService.trySpeakDetection(top, currentRisk: currentRisk);
      // מנסה להשמיע התראה קולית עם שם האובייקט

      await Future.delayed(const Duration(milliseconds: 300));
      await _resumeListening();
      // מחזיר את ההאזנה לפקודות קוליות
    });
  }

  /// מחזיר את רמת ההתראה המתאימה לפי ציון הסיכון ומצב תנועת המשתמש
  _AlertLevel _getAlertLevel(Detection detection) {
    final riskScore = detection.riskScore;

    // המשתמש עומד → רק סכנה גבוהה מאוד תוביל להתראה
    if (!_userIsMoving) {
      if (riskScore >= _beepAlertThreshold) return _AlertLevel.beepAndVoice;
      // עומד + סיכון גבוה מאוד → צפצוף + קול
      if (riskScore >= _voiceAlertThreshold) return _AlertLevel.voiceOnly;
      // עומד + סיכון בינוני → קול בלבד (ללא צפצוף)
      return _AlertLevel.none;
      // עומד + סיכון נמוך → שקט
    }

    // המשתמש הולך → מגיב לפי כל הרמות
    if (riskScore >= _beepAlertThreshold) return _AlertLevel.beepAndVoice;
    // הולך + סיכון גבוה → צפצוף + קול + רטט
    if (riskScore >= _voiceAlertThreshold) return _AlertLevel.voiceOnly;
    // הולך + סיכון בינוני → קול + רטט
    if (riskScore >= _vibrationOnlyThreshold) return _AlertLevel.vibrationOnly;
    // הולך + סיכון נמוך → רטט בלבד
    return _AlertLevel.none;
    // מתחת לסף המינימלי → שקט לגמרי
  }

  void _handleVoiceCommand(String command) {
    // פונקציה שמקבלת טקסט מזוהה מהקול ומחליטה איזו פעולה לבצע
    if (kDebugMode) debugPrint('🎤 נשמע: "$command"');

    final text = command.toLowerCase().trim();
    // ממיר לאותיות קטנות ומנקה רווחים מיותרים כדי להקל על ההשוואה

    final List<String> startCommands = _isHebrew
        ? [
      'הפעל', 'הפעל זיהוי', 'הפעלה', 'הפעלה זיהוי',
      'התחל', 'התחל זיהוי',
      'תתחיל', 'תתחיל זיהוי',
      'תפעיל', 'תפעיל זיהוי',
      'תדליק', 'תדליק זיהוי',
      'התחיל', 'התחיל זיהוי',
      'הפעיל', 'הפעיל זיהוי',
      'להתחיל', 'להפעיל',
      'פתח', 'פתח זיהוי', 'פתיחה',
      'הדלק', 'הדלק זיהוי',
      'אפעיל', 'אתחיל',
      'זיהוי', 'התחל לזהות', 'תתחיל לזהות',
    ]
        : [
      'start', 'start detection', 'begin', 'begin detection',
      'activate', 'activate detection', 'turn on', 'turn on detection',
      'run', 'run detection', 'go', 'detect', 'open detection',
    ];
    // ביטויים להפעלת זיהוי לפי השפה שנבחרה

    final List<String> stopCommands = _isHebrew
        ? [
      'עצור', 'עצור זיהוי',
      'הפסק', 'הפסק זיהוי',
      'כבה', 'כבה זיהוי',
      'תעצור', 'תעצור זיהוי',
      'תפסיק', 'תפסיק זיהוי',
      'תכבה', 'תכבה זיהוי',
      'עצר', 'עצרתי', 'הפסיק', 'כיבה',
      'לעצור', 'להפסיק', 'לכבות',
      'סגור', 'סגור זיהוי', 'סיים', 'סיים זיהוי',
      'די', 'די זיהוי', 'מספיק',
      'אעצור', 'אפסיק',
    ]
        : [
      'stop', 'stop detection', 'pause', 'pause detection',
      'turn off', 'turn off detection', 'disable', 'disable detection',
      'end', 'end detection', 'quit', 'halt',
    ];
    // ביטויים לעצירת זיהוי לפי השפה שנבחרה

    final List<String> settingsCommands = _isHebrew
        ? [
      'הגדרות', 'פתח הגדרות', 'תפתח הגדרות',
      'מסך הגדרות', 'להגדרות', 'כנס להגדרות',
      'תכנס להגדרות', 'פתח את ההגדרות',
    ]
        : [
      'settings', 'open settings', 'show settings',
      'go to settings', 'settings screen', 'preferences',
    ];
    // ביטויים לפתיחת הגדרות לפי השפה שנבחרה

    final List<String> vibrationOnCommands = _isHebrew
        ? [
      'הפעל רטט', 'תפעיל רטט', 'רטט פעיל',
      'תדליק רטט', 'הדלק רטט', 'רטט כן',
      'הפעל את הרטט', 'תפעיל את הרטט',
    ]
        : [
      'turn on vibration', 'enable vibration', 'vibration on',
      'activate vibration', 'start vibration',
    ];
    // ביטויים להפעלת רטט לפי השפה שנבחרה

    final List<String> vibrationOffCommands = _isHebrew
        ? [
      'כבה רטט', 'תכבה רטט', 'רטט כבוי',
      'תפסיק רטט', 'עצור רטט', 'בלי רטט',
      'כבה את הרטט', 'תכבה את הרטט', 'ללא רטט',
    ]
        : [
      'turn off vibration', 'disable vibration', 'vibration off',
      'stop vibration', 'no vibration',
    ];
    // ביטויים לכיבוי רטט לפי השפה שנבחרה

    bool containsAny(List<String> commands) {
      return commands.any((phrase) => text.contains(phrase));
    }
    // פונקציית עזר שבודקת האם הטקסט שנאמר מכיל אחד מהביטויים ברשימה

    if (containsAny(startCommands)) {
      if (!_isRunning) _startDetection();
    } else if (containsAny(stopCommands)) {
      if (_isRunning) _stopDetection();
    } else if (containsAny(settingsCommands)) {
      _openSettings();
    } else if (containsAny(vibrationOnCommands)) {
      setState(() => _vibrationEnabled = true);
    } else if (containsAny(vibrationOffCommands)) {
      setState(() => _vibrationEnabled = false);
    }
  }

  Future<void> _handleVibration(String tag) async {
    // פונקציה שמפעילה רטט בהתאם לסוג האובייקט שזוהה
    if (!_vibrationEnabled) return;
    // אם המשתמש כיבה רטט → לא עושים כלום

    final now = DateTime.now();
    if (_lastVibrationTime != null &&
        now.difference(_lastVibrationTime!) < _vibrationCooldown) {
      return;
      // אם לא עבר מספיק זמן מאז הרטט האחרון → לא מרטיטים שוב
    }

    try {
      if (!(await Vibration.hasVibrator() ?? false)) return;
      // אם למכשיר אין רטט → יוצאים

      int duration; // משך הרטט (במילישניות)

      switch (tag) {
        case 'car':
        case 'bus':
        case 'truck':
        case 'train':
        case 'motorcycle':
          duration = 400;
          break;
      // רכבים → רטט ארוך (מסוכן יותר)

        case 'person':
        case 'bicycle':
        case 'skateboard':
          duration = 250;
          break;
      // אנשים/תחבורה קלה → בינוני

        case 'traffic light':
        case 'stop sign':
        case 'fire hydrant':
          duration = 150;
          break;
      // תמרורים ותשתית → קצר

        case 'dog':
        case 'cat':
        case 'horse':
        case 'sheep':
        case 'cow':
        case 'elephant':
        case 'bear':
        case 'zebra':
        case 'giraffe':
        case 'bird':
          duration = 200;
          break;
      // בעלי חיים → בינוני

        case 'bench':
        case 'chair':
        case 'couch':
        case 'bed':
        case 'dining table':
        case 'potted plant':
          duration = 300;
          break;
      // ריהוט → בינוני-גבוה

        case 'backpack':
        case 'handbag':
        case 'suitcase':
        case 'umbrella':
          duration = 180;
          break;
      // חפצים אישיים → בינוני-נמוך

        case 'skis':
        case 'sports ball':
        case 'surfboard':
        case 'tennis racket':
          duration = 120;
          break;
      // ציוד ספורט → קצר

        default:
          duration = 100;
      // ברירת מחדל → רטט קצר מאוד
      }

      await Vibration.vibrate(duration: duration);
      // הפעלת הרטט בפועל

      _lastVibrationTime = now;
      // שמירת זמן הרטט האחרון כדי למנוע spam

    } catch (e) {
      if (kDebugMode) debugPrint('Vibration error: $e');
      // הדפסת שגיאה רק במצב debug
    }
  }

  Future<void> _stopDetection() async {
    // פונקציה שמפסיקה את תהליך הזיהוי וכל השירותים הקשורים אליו
    if (!_isRunning) return;
    // אם המערכת לא רצה כרגע - אין מה לעצור

    await _cameraService.stopStream();
    // עוצר את זרם הפריימים מהמצלמה

    await _voiceService.stopListening();
    // עוצר את ההאזנה לפקודות קוליות

    _alertService.resetSpeakingState();
    // מאפס מצב דיבור והתראות

    _riskScoringService.reset();
    // מאפס את שירות חישוב הסיכון

    await _alertService.speakSystemStopped();
    // משמיע הודעה קולית שהמערכת הופסקה

    setState(() {
      _isRunning = false;
      // מעדכן שהמערכת כבר לא פועלת

      _currentMostDangerous = null;
      // מאפס את האובייקט המסוכן המוצג

      _displayManager.clearDisplayStart();
      // מאפס את זמן תחילת התצוגה
    });

    await Future.delayed(const Duration(milliseconds: 800));
    await _resumeListening();
    // מחזיר האזנה לפקודות קוליות
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      // פותח מסך חדש מעל המסך הנוכחי
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          speechRate: _speechRate,
          vibrationEnabled: _vibrationEnabled,
          language: _language,
          voices: _voices,
          selectedVoice: _selectedVoice,

          onVoiceTest: () async {
            // callback לבדיקת קול מתוך מסך ההגדרות
            await _applyTtsSettings();
            await _alertService.speakVoiceTest();
          },

          onChanged: (speechRate, vibrationEnabled, language, selectedVoice) async {
            // callback שמקבל ערכים חדשים ממסך ההגדרות
            _speechRate = speechRate;
            _vibrationEnabled = vibrationEnabled;
            _language = language;
            _selectedVoice = selectedVoice;

            await _applyTtsSettings();
            // מחיל בפועל את ההגדרות החדשות

            if (mounted) setState(() {});
            // אם המסך עדיין קיים - מבצע rebuild
          },
        ),
      ),
    );
  }

  String _localizedObjectName() {
    // מחזיר את שם האובייקט המסוכן בשפה הנוכחית, או הודעה שאין אובייקט
    if (_currentMostDangerous == null) {
      return _isHebrew
          ? 'אין אובייקט מסוכן כרגע'
          : 'No dangerous object detected';
    }
    return _alertService.localizedLabel(_currentMostDangerous!.tag);
    // מחזיר את שם האובייקט המתורגם דרך AlertService
  }

  String _localizedRiskLevel(double riskScore) {
    // ממיר ציון סיכון מספרי לטקסט מתאים בשפה הנוכחית
    if (_isHebrew) {
      if (riskScore >= 75) return 'גבוהה';
      if (riskScore >= 50) return 'בינונית';
      return 'נמוכה';
    }
    if (riskScore >= 75) return 'High';
    if (riskScore >= 50) return 'Medium';
    return 'Low';
  }

  Color _riskColor(double? riskScore) {
    // מחזיר צבע בהתאם לרמת הסיכון
    if (riskScore == null) return Colors.grey; // אין ציון - אפור
    if (riskScore >= 75) return const Color(0xFFFF5A5F); // גבוה - אדום
    if (riskScore >= 50) return const Color(0xFFFFA726); // בינוני - כתום
    return const Color(0xFF66BB6A); // נמוך - ירוק
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    // ביטול האזנה לאקסלרומטר כדי למנוע דליפת זיכרון

    _cameraService.dispose(); // שחרור משאבי המצלמה
    _yoloService.dispose(); // שחרור משאבי מודל הזיהוי
    _alertService.stop(); // עצירת דיבור/התראות
    _tts.stop(); // עצירת מנוע TTS המקומי
    _voiceService.stopListening(); // עצירת האזנה לפקודות קוליות
    super.dispose(); // קריאה ל-dispose של המחלקה האב
  }

  @override
  Widget build(BuildContext context) {
    // פונקציה שמחזירה את ה-UI של המסך בכל רגע נתון
    if (!_isInitialized) {
      // אם המערכת עדיין לא אותחלה → מציג מסך טעינה
      return Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: primaryColor),
              // עיגול טעינה
              const SizedBox(height: 16),
              Text(
                _isHebrew ? 'מאתחל מערכת...' : 'Initializing...',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final buttonText = _isRunning
        ? (_isHebrew ? 'עצור זיהוי' : 'Stop')
        : (_isHebrew ? 'הפעל זיהוי' : 'Start');
    // טקסט הכפתור לפי מצב המערכת והשפה

    final objectText = _localizedObjectName();
    // שם האובייקט המסוכן (או הודעה שאין)

    final currentRiskScore = _currentMostDangerous?.riskScore;
    // ציון הסיכון (יכול להיות null)

    final currentRiskColor = _riskColor(currentRiskScore);
    // צבע בהתאם לרמת הסיכון

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115), // צבע רקע כהה
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1115),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Safe Step',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Material(
              color: const Color(0xFF1B1F27),
              borderRadius: BorderRadius.circular(12),
              child: IconButton(
                onPressed: _openSettings,
                // בלחיצה פותח את מסך ההגדרות
                icon: const Icon(Icons.settings_rounded,
                    color: Colors.white, size: 22),
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        // מונע חפיפה עם notch/סטטוס בר
        child: SingleChildScrollView(
          // מאפשר גלילה אם התוכן גדול מהמסך
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              _buildMainButton(buttonText),
              // כפתור הפעלה/עצירה
              const SizedBox(height: 16),
              _buildDangerCard(objectText, currentRiskColor),
              // כרטיס שמציג את האובייקט והסיכון
              const SizedBox(height: 16),
              _buildStatusRow(),
              // שורת סטטוס (רטט + שפה)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton(String buttonText) {
    // פונקציה שבונה את כפתור ההפעלה הראשי
    return SizedBox(
      width: double.infinity, // הכפתור תופס את כל הרוחב
      height: 120,
      child: ElevatedButton(
        onPressed: _isRunning ? _stopDetection : _startDetection,
        // אם המערכת רצה → עוצר, אחרת → מפעיל

        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRunning
                  ? Icons.stop_circle_rounded
                  : Icons.play_circle_fill_rounded,
              // אייקון עצור או הפעל לפי המצב
              size: 40,
            ),
            const SizedBox(width: 16),
            Text(buttonText),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerCard(String objectText, Color currentRiskColor) {
    // פונקציה שבונה כרטיס שמציג את האובייקט המסוכן ביותר והמידע עליו
    return _glassCard(
      child: Column(
        children: [
          Text(
            _isHebrew ? 'האובייקט המסוכן ביותר' : 'Most dangerous object',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 16),

          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            // אנימציה חלקה כשמשתנה צבע הסיכון
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: currentRiskColor.withOpacity(0.14),
              // צבע רקע שקוף לפי רמת הסיכון
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: currentRiskColor,
              size: 46,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            objectText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 18),

          if (_currentMostDangerous != null) ...[
            // אם יש אובייקט מזוהה → מציגים נתונים
            _buildMetricTile(
              title: _isHebrew ? 'רמת סיכון' : 'Risk level',
              value: _localizedRiskLevel(_currentMostDangerous!.riskScore),
              valueColor: currentRiskColor,
              icon: Icons.shield_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricTile(
              title: _isHebrew ? 'רמת זיהוי' : 'Detection confidence',
              value:
              '${(_currentMostDangerous!.confidence * 100).toStringAsFixed(0)}%',
              // הופך ערך 0-1 לאחוזים
              icon: Icons.analytics_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricTile(
              title: _isHebrew ? 'ניקוד סיכון' : 'Risk score',
              value: _currentMostDangerous!.riskScore.toStringAsFixed(1),
              // ציון עם ספרה אחת אחרי הנקודה
              icon: Icons.bar_chart_rounded,
            ),
          ] else ...[
            // אם אין אובייקט מזוהה
            Text(
              _isHebrew
                  ? 'המערכת ממתינה לזיהוי חדש.'
                  : 'The system is waiting for a new detection.',
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    // פונקציה שבונה שורת סטטוס קטנה שמציגה מידע על רטט ושפה
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        // מסגרת דקה כמעט שקופה
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        // מפזר את האלמנטים באופן שווה
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.vibration,
                size: 18,
                color: _vibrationEnabled
                    ? const Color(0xFFBA68C8)
                // רטט פעיל → סגול
                    : Colors.grey.withOpacity(0.4),
                // רטט כבוי → אפור שקוף
              ),
              const SizedBox(width: 6),
              Text(
                _isHebrew
                    ? 'רטט: ${_vibrationEnabled ? "פעיל" : "כבוי"}'
                    : 'Vib: ${_vibrationEnabled ? "On" : "Off"}',
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ],
          ),

          Container(width: 1, height: 20, color: Colors.white.withOpacity(0.2)),
          // קו הפרדה אנכי בין שני החלקים

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language_rounded,
                  size: 18, color: Color(0xFF64B5F6)),
              // אייקון שפה בצבע כחול
              const SizedBox(width: 6),
              Text(
                _isHebrew ? 'שפה: עברית' : 'Lang: English',
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    // פונקציה שבונה כרטיס מעוצב עם עיצוב אחיד
    return Container(
      padding: const EdgeInsets.all(20),
      // רווח פנימי מכל הצדדים
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(26),
        // פינות מעוגלות מאוד
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        // מסגרת דקה כמעט שקופה
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            // צל מטושטש
            offset: const Offset(0, 10),
            // הצל יורד למטה
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMetricTile({
    required String title, // כותרת המדד
    required String value, // ערך המדד
    required IconData icon, // האייקון
    Color valueColor = Colors.white, // צבע הערך (ברירת מחדל לבן)
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        // רקע לבן מאוד שקוף
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryColor, size: 22),
            // אייקון בצבע כתום
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor,
              // צבע דינמי לפי רמת הסיכון
            ),
          ),
        ],
      ),
    );
  }
}

/// רמות ההתראה האפשריות לפי ציון הסיכון
enum _AlertLevel {
  none,
  // מתחת ל-30: שקט לגמרי

  vibrationOnly,
  // 30–40: רטט בלבד, ללא קול

  voiceOnly,
  // 40–65: רטט + שם האובייקט בקול

  beepAndVoice,
  // מעל 65: רטט + צפצוף + שם האובייקט בקול
}