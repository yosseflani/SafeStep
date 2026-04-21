import 'package:camera/camera.dart'; // ספריית מצלמה – מאפשרת עבודה עם CameraImage, שליטה במצלמה וכו'
import 'package:flutter/foundation.dart'; // כלים בסיסיים של Flutter (כמו kDebugMode)
import 'package:flutter/material.dart'; // רכיבי UI של Flutter (כפתורים, טקסטים, צבעים וכו')
import 'package:flutter_tts/flutter_tts.dart'; // ספריית Text To Speech – דיבור בקול
import 'package:vibration/vibration.dart'; // ספריית רטט – מאפשרת להפעיל vibration במכשיר

import '../models/detection.dart'; // מודל שמייצג אובייקט שזוהה (Detection)
import '../services/alert_service.dart'; // שירות שמנהל התראות קוליות
import '../services/camera_service.dart'; // שירות שמנהל את המצלמה
import '../services/cooldown_manager.dart'; // מנהל זמן בין התראות (כדי לא להציף)
import '../services/risk_scoring_service.dart'; // שירות שמחשב רמת סיכון
import '../services/yolo_service.dart'; // שירות שמריץ את מודל YOLO לזיהוי אובייקטים
import '../services/voice_command_service.dart';// ייבוא שירות שמטפל בזיהוי פקודות קוליות (Speech-to-Text)
import '../services/display_manager.dart'; // ייבוא המחלקה DisplayManager שאחראית על לוגיקת זמן התצוגה והחלטה מתי לעדכן
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
  final DisplayManager _displayManager = DisplayManager(); // יצירת מופע (instance) של DisplayManager כדי להשתמש בו בתוך המסך
  final VoiceCommandService _voiceService = VoiceCommandService(); // יצירת מופע של שירות הפקודות הקוליות

  DateTime? _lastVibrationTime; // זמן הרטט האחרון
  static const _vibrationCooldown = Duration(
      milliseconds: 500); // זמן מינימלי בין רטטים

  bool _isInitialized = false; // האם המערכת כבר אותחלה
  bool _isRunning = false; // האם הזיהוי כרגע פועל

  double _speechRate = 0.5; // מהירות דיבור
  bool _vibrationEnabled = true; // האם רטט פעיל
  String _language = 'he-IL'; // שפה (עברית)
  String? _selectedVoice; // קול נבחר (יכול להיות null)
  List<Map<String, dynamic>> _voices = []; // רשימת קולות זמינים

  Detection? _currentMostDangerous; // האובייקט הכי מסוכן כרגע (או null)

  bool get _isHebrew =>
      _language.startsWith('he'); // getter: בודק אם השפה עברית

  @override
  void initState() {
    // פונקציה שנקראת פעם אחת כשהמסך נוצר
    super.initState(); // קריאה ל־initState של המחלקה האב
    _initializeSystem(); // אתחול המערכת (מצלמה, מודל וכו')
  }

  Future<void> _initializeSystem() async {
    // פונקציה אסינכרונית שמבצעת אתחול של כל המערכת
    try { // בלוק try – מנסה להריץ קוד שעלול לזרוק שגיאה

      await Future.wait([ // מריץ כמה פעולות אסינכרוניות במקביל ומחכה שכולן יסתיימו לפני המשך הקוד
        _cameraService.initialize(), // אתחול המצלמה (פתיחת גישה למצלמה והכנתה לצילום)

        _yoloService.initModel(), // טעינת מודל YOLO לזיהוי אובייקטים (מודל כבד ולכן נעשה פעם אחת)

        _voiceService.initialize(),
        // אתחול שירות זיהוי הקול (בודק הרשאות ומכין את מנוע ה-Speech-to-Text)

        _alertService.initialize( // אתחול שירות ההתראות הקוליות (TTS)
          language: _language, // קובע באיזו שפה המערכת תדבר
          speechRate: _speechRate, // קובע את מהירות הדיבור
          voiceAlertsEnabled: true, // מפעיל אפשרות של התראות קוליות
        ),
      ]);

      final controller = _cameraService
          .controller; // מביא את ה-controller של המצלמה

      if (controller?.value.previewSize !=
          null) { // בדיקה שהמצלמה מאותחלת ויש גודל תצוגה
        _riskScoringService
            .updateResolution( // מעדכן את שירות חישוב הסיכון ברזולוציה
          controller!.value.previewSize!.width.toInt(), // רוחב התמונה
          controller.value.previewSize!.height.toInt(), // גובה התמונה
        );
      }

      final raw = await _tts.getVoices ??
          []; // מביא רשימת קולות מה-TTS (אם null אז רשימה ריקה)

      _voices = raw.whereType<Map<String, dynamic>>().toList();
      // מסנן רק איברים שהם Map<String, dynamic> והופך לרשימה

      await _applyTtsSettings(); // מיישם את הגדרות ה-TTS (שפה, קול וכו')

      if (!mounted) return; // אם ה-Widget כבר לא קיים בעץ – לא ממשיכים

      setState(() => _isInitialized = true);
      // מעדכן את ה-state: המערכת מוכנה

      //  התחלת האזנה לפקודות קוליות
      await _resumeListening();

    } catch (e, stack) { // אם קרתה שגיאה

      if (kDebugMode) debugPrint('Init error: $e\n$stack');
      // הדפסה לקונסול רק במצב debug

      if (!mounted) return; // שוב בדיקה שה-widget עדיין קיים

      setState(() {}); // גורם ל-rebuild (גם בלי שינוי ערכים)

      ScaffoldMessenger.of(context).showSnackBar( // מציג הודעת שגיאה למשתמש
        SnackBar(
          content: Text(
              _isHebrew
                  ? 'שגיאה באתחול המערכת'
                  : 'System initialization error'
          ), // הודעה בהתאם לשפה

          backgroundColor: Colors.red.shade900, // רקע אדום כהה

          action: SnackBarAction( // כפתור בתוך ההודעה
            label: _isHebrew ? 'נסה שוב' : 'Retry', // טקסט לפי שפה
            textColor: Colors.white,
            onPressed: _initializeSystem, // לחיצה מפעילה שוב את האתחול
          ),
        ),
      );
    }
  }

  Future<void> _applyTtsSettings() async {
    // פונקציה אסינכרונית שמחילה את הגדרות הקול
    try { // מנסה להריץ את הקוד, ואם תהיה שגיאה נעבור ל-catch
      await _tts.setLanguage(_language); // מגדיר את שפת הדיבור במנוע ה-TTS
      await _tts.setSpeechRate(_speechRate.clamp(
          0.1, 2.0)); // מגדיר את מהירות הדיבור, עם הגבלה לטווח תקין

      if (_selectedVoice != null) { // רק אם המשתמש בחר קול מסוים
        await _tts.setVoice(
            {'name': _selectedVoice!}); // מגדיר את הקול הנבחר במנוע ה-TTS
      }

      await _alertService
          .updateSettings( // מעדכן גם את שירות ההתראות עם אותן הגדרות
        language: _language,
        speechRate: _speechRate,
        voiceAlertsEnabled: true,
      );
    } catch (e) { // אם קרתה שגיאה באחת הפעולות
      if (kDebugMode) debugPrint(
          'TTS settings error: $e'); // מדפיס את השגיאה רק במצב debug
    }
  }

  Future<void> _resumeListening() async {
    if (!mounted) return;

    if (_alertService.isSpeaking) return;
    if (_voiceService.isListening) return;

    await _voiceService.startListening(
      _handleVoiceCommand,
      localeId: _isHebrew ? 'he_IL' : 'en_US',
    );
  }

  Future<void> _startDetection() async {
    // פונקציה שמתחילה את תהליך הזיהוי

    if (!_isInitialized || _isRunning)
      return; // אם המערכת לא אותחלה או שכבר פועלת - לא ממשיכים

    await _alertService.speakSystemStarted();
    // משמיע הודעה שהמערכת התחילה

    if (_vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
      // אם רטט מופעל ולמכשיר יש רטט
      Vibration.vibrate(duration: 100);
      // מרטיט לזמן קצר כסימן להתחלה
    }

    setState(() {
      _isRunning = true;
      // מעדכן שהמערכת כרגע רצה
    });


    await _cameraService.startStream((CameraImage image) async {
      // מתחיל stream מהמצלמה; כל פריים נכנס לכאן

      final detections = await _yoloService.detectObjects(
        // שולח את הפריים למודל הזיהוי
        image.planes.map((plane) => plane.bytes).toList(),
        // ממיר את נתוני התמונה ל-bytes
        image.height, // גובה התמונה
        image.width, // רוחב התמונה
      );

      _riskScoringService.updateResolution(
          image.width, image.height);
      // מעדכן את הרזולוציה לשירות הסיכון

      final scored = _riskScoringService.scoreDetections(detections);
      // מחשב ניקוד סיכון לכל זיהוי

      final top = scored.isNotEmpty ? scored.first : null;
      // בוחר את האובייקט הכי מסוכן, או null אם אין

      if (!mounted) return;
      // אם המסך כבר לא קיים - עוצרים

      // NEW: לוגיקת החזקת תצוגה עם זמן מינימלי
      final shouldUpdateDisplay = _displayManager.shouldUpdateDisplay(
        // בודק האם לעדכן את התצוגה
        hasCurrentObject: _currentMostDangerous != null,
        newRisk: top?.riskScore,
        currentRisk: _currentMostDangerous?.riskScore,
      );

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

      if (top != null && _cooldownManager.canAlert(top.tag)) {
        // אם יש אובייקט ומותר להתריע עליו

        _cooldownManager.markAlerted(top.tag);
        // מסמן שכבר התרענו על התג הזה

        final currentRisk = _currentMostDangerous?.riskScore;
        // שומר את רמת הסיכון הנוכחית

        //  עוצרים האזנה בזמן שהאפליקציה מדברת
        await _voiceService.stopListening();
        // חשוב כדי למנוע מצב שהאפליקציה שומעת את עצמה

        await _alertService.trySpeakDetection(
            top, currentRisk: currentRisk);
        // מנסה להשמיע התראה קולית

        await _handleVibration(top.tag);
        // מפעיל רטט לפי סוג האובייקט

        await Future.delayed(const Duration(milliseconds: 300));
        await _resumeListening();
      }
    });
  }
  void _handleVoiceCommand(String command) {
    // פונקציה שמקבלת טקסט מזוהה מהקול ומחליטה איזו פעולה לבצע לפי השפה שנבחרה

    final text = command.toLowerCase().trim();
    // ממיר לאותיות קטנות ומנקה רווחים מיותרים כדי להקל על ההשוואה

    // ביטויים להפעלת זיהוי לפי השפה שנבחרה
    final List<String> startCommands = _isHebrew
        ? [
      'הפעל',
      'הפעלה',
      'הפעל זיהוי',
      'הפעלה זיהוי',
      'התחל',
      'התחל זיהוי',
      'תתחיל',
      'תתחיל זיהוי',
      'תפעיל',
      'תפעיל זיהוי',
    ]
        : [
      'start',
      'start detection',
      'begin',
      'begin detection',
      'activate',
      'activate detection',
      'turn on detection',
      'run detection',
    ];

    // ביטויים לעצירת זיהוי לפי השפה שנבחרה
    final List<String> stopCommands = _isHebrew
        ? [
      'עצור',
      'עצור זיהוי',
      'הפסק',
      'הפסק זיהוי',
      'כבה',
      'כבה זיהוי',
      'תעצור',
      'תפסיק',
    ]
        : [
      'stop',
      'stop detection',
      'pause',
      'pause detection',
      'turn off',
      'turn off detection',
      'disable detection',
    ];

    // ביטויים לפתיחת הגדרות לפי השפה שנבחרה
    final List<String> settingsCommands = _isHebrew
        ? [
      'הגדרות',
      'פתח הגדרות',
      'תפתח הגדרות',
      'מסך הגדרות',
    ]
        : [
      'settings',
      'open settings',
      'show settings',
      'settings screen',
    ];

    // ביטויים להפעלת רטט
    final List<String> vibrationOnCommands = _isHebrew
        ? [
      'הפעל רטט',
      'תפעיל רטט',
      'רטט פעיל',
      'תדליק רטט',
    ]
        : [
      'turn on vibration',
      'enable vibration',
      'vibration on',
    ];

    // ביטויים לכיבוי רטט
    final List<String> vibrationOffCommands = _isHebrew
        ? [
      'כבה רטט',
      'תכבה רטט',
      'רטט כבוי',
      'תפסיק רטט',
    ]
        : [
      'turn off vibration',
      'disable vibration',
      'vibration off',
    ];

    bool containsAny(List<String> commands) {
      return commands.any((phrase) => text.contains(phrase));
    }
    // פונקציית עזר שבודקת האם הטקסט שנאמר מכיל אחד מהביטויים ברשימה

    if (containsAny(startCommands)) {
      if (!_isRunning) {
        _startDetection();
      }
    } else if (containsAny(stopCommands)) {
      if (_isRunning) {
        _stopDetection();
      }
    } else if (containsAny(settingsCommands)) {
      _openSettings();
    } else if (containsAny(vibrationOnCommands)) {
      setState(() {
        _vibrationEnabled = true;
      });
    } else if (containsAny(vibrationOffCommands)) {
      setState(() {
        _vibrationEnabled = false;
      });
    }
  }

  Future<void> _handleVibration(String tag) async {
    if (!_vibrationEnabled) return; // אם המשתמש כיבה רטט → לא עושים כלום

    //  מניעת רטט בתדירות גבוהה מדי
    final now = DateTime.now(); // הזמן הנוכחי
    if (_lastVibrationTime != null &&
        now.difference(_lastVibrationTime!) < _vibrationCooldown) {
      return; // אם לא עבר מספיק זמן מאז הרטט האחרון → לא מרטיטים שוב
    }

    try {
      if (!(await Vibration.hasVibrator() ?? false))
        return; // אם למכשיר אין רטט → יוצאים

      int duration; // משך הרטט (במילישניות)

      switch (tag) { // קביעת משך הרטט לפי סוג האובייקט
        case 'car':
        case 'bus':
        case 'truck':
        case 'train':
        case 'motorcycle':
          duration = 400;
          break; // רכבים → רטט ארוך (מסוכן יותר)

        case 'person':
        case 'bicycle':
        case 'skateboard':
          duration = 250;
          break; // אנשים/תנועה → בינוני

        case 'traffic light':
        case 'stop sign':
        case 'fire hydrant':
          duration = 150;
          break; // תמרורים → קצר

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
          break; // חיות → בינוני

        case 'bench':
        case 'chair':
        case 'couch':
        case 'bed':
        case 'dining table':
        case 'potted plant':
          duration = 300;
          break; // רהיטים → בינוני-גבוה

        case 'backpack':
        case 'handbag':
        case 'suitcase':
        case 'umbrella':
          duration = 180;
          break; // חפצים אישיים → בינוני-נמוך

        case 'skis':
        case 'sports ball':
        case 'surfboard':
        case 'tennis racket':
          duration = 120;
          break; // ציוד ספורט → קצר

        default:
          duration = 100; // ברירת מחדל → רטט קצר מאוד
      }

      await Vibration.vibrate(duration: duration); // הפעלת הרטט בפועל

      _lastVibrationTime = now; //  שמירת זמן הרטט האחרון כדי למנוע spam

    } catch (e) {
      if (kDebugMode) debugPrint(
          'Vibration error: $e'); // הדפסת שגיאה רק במצב debug
    }
  }

  Future<void> _stopDetection() async {
    // פונקציה שמפסיקה את תהליך הזיהוי וכל השירותים הקשורים אליו

    if (!_isRunning) return;
    // אם המערכת לא רצה כרגע - אין מה לעצור

    await _cameraService.stopStream();
    // עוצר את זרם הפריימים מהמצלמה (מפסיק את הזיהוי בפועל)

    await _voiceService.stopListening();
    //  עוצר את ההאזנה לפקודות קוליות (מכבה את המיקרופון)

    _alertService.resetSpeakingState();
    // מאפס מצב דיבור והתראות (מונע המשך דיבור או תורים מיותרים)

    _riskScoringService.reset();
    // מאפס את שירות חישוב הסיכון (מוחק נתונים קודמים)

    await _alertService.speakSystemStopped();
    // משמיע הודעה קולית שהמערכת הופסקה

    setState(() {
      _isRunning = false;
      // מעדכן שהמערכת כבר לא פועלת

      _currentMostDangerous = null;
      // מאפס את האובייקט המסוכן המוצג

      _displayManager.clearDisplayStart();
      // מאפס את זמן תחילת התצוגה (כדי לא להשאיר מידע ישן)
    });

    await Future.delayed(const Duration(milliseconds: 300));
    await _resumeListening();

  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push( // פותח מסך חדש מעל המסך הנוכחי
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen( // בונה את מסך ההגדרות
              speechRate: _speechRate,
              // שולח את מהירות הדיבור הנוכחית
              vibrationEnabled: _vibrationEnabled,
              // שולח האם רטט פעיל
              language: _language,
              // שולח את השפה הנוכחית
              voices: _voices,
              // שולח את רשימת הקולות הזמינים
              selectedVoice: _selectedVoice,
              // שולח את הקול שנבחר כרגע

              onVoiceTest: () async { // callback לבדיקת קול מתוך מסך ההגדרות
                await _applyTtsSettings(); // מחיל את הגדרות ה-TTS הנוכחיות
                await _alertService.speakVoiceTest(); // משמיע הודעת בדיקת קול
              },

              onChanged: (speechRate, vibrationEnabled, language,
                  selectedVoice) async {
                // callback שמקבל ערכים חדשים ממסך ההגדרות
                _speechRate = speechRate; // עדכון מהירות דיבור
                _vibrationEnabled = vibrationEnabled; // עדכון מצב רטט
                _language = language; // עדכון שפה
                _selectedVoice = selectedVoice; // עדכון קול נבחר

                await _applyTtsSettings(); // מחיל בפועל את ההגדרות החדשות

                if (mounted) setState(() {}); // אם המסך עדיין קיים - מבצע rebuild
              },
            ),
      ),
    );
  }

  String _localizedObjectName() {
    if (_currentMostDangerous == null) { // אם אין כרגע אובייקט מסוכן
      return _isHebrew
          ? 'אין אובייקט מסוכן כרגע'
          : 'No dangerous object detected'; // מחזיר טקסט לפי השפה
    }
    return _alertService.localizedLabel(_currentMostDangerous!.tag);
    // מחזיר את שם האובייקט המתורגם דרך AlertService
  }

  String _localizedRiskLevel(double riskScore) {
    if (_isHebrew) { // אם השפה עברית
      if (riskScore >= 75) return 'גבוהה'; // סיכון גבוה
      if (riskScore >= 50) return 'בינונית'; // סיכון בינוני
      return 'נמוכה'; // סיכון נמוך
    }
    if (riskScore >= 75) return 'High'; // באנגלית - גבוה
    if (riskScore >= 50) return 'Medium'; // באנגלית - בינוני
    return 'Low'; // באנגלית - נמוך
  }

  Color _riskColor(double? riskScore) {
    if (riskScore == null) return Colors.grey; // אם אין ציון סיכון - צבע אפור
    if (riskScore >= 75) return const Color(0xFFFF5A5F); // סיכון גבוה - אדום
    if (riskScore >= 50) return const Color(0xFFFFA726); // סיכון בינוני - כתום
    return const Color(0xFF66BB6A); // סיכון נמוך - ירוק
  }

  @override
  void dispose() {
    _cameraService.dispose(); // שחרור משאבי המצלמה
    _yoloService.dispose(); // שחרור משאבי מודל הזיהוי
    _alertService.stop(); // עצירת דיבור/התראות
    _tts.stop(); // עצירת מנוע TTS המקומי
    _voiceService.stopListening();
    super.dispose(); // קריאה ל-dispose של המחלקה האב
  }

  @override
  Widget build(BuildContext context) {
    // פונקציה שמחזירה את ה-UI של המסך בכל רגע נתון
    if (!_isInitialized) { // אם המערכת עדיין לא אותחלה (מצלמה/מודל וכו')
      return Scaffold( // מחזיר מסך טעינה במקום המסך הראשי
        backgroundColor: const Color(0xFF0F1115), // צבע רקע כהה
        body: Center( // ממקם את התוכן במרכז המסך
          child: Column( // מסדר את האלמנטים בעמודה (מלמעלה למטה)
            mainAxisAlignment: MainAxisAlignment.center,
            // ממקם את כל התוכן באמצע אנכית
            children: [
              const CircularProgressIndicator(color: primaryColor),
              // עיגול טעינה
              const SizedBox(height: 16),
              // רווח של 16 פיקסלים
              Text(
                _isHebrew ? 'מאתחל מערכת...' : 'Initializing...',
                // טקסט לפי שפה
                style: const TextStyle(color: Colors.white70), // צבע טקסט בהיר
              ),
            ],
          ),
        ),
      );
    }

    // חישוב טקסט הכפתור לפי מצב המערכת והשפה
    final buttonText = _isRunning
        ? (_isHebrew ? 'עצור זיהוי' : 'Stop') // אם המערכת רצה
        : (_isHebrew ? 'הפעל זיהוי' : 'Start'); // אם המערכת לא רצה

    final objectText = _localizedObjectName(); // שם האובייקט המסוכן (או הודעה שאין)
    final currentRiskScore = _currentMostDangerous
        ?.riskScore; // ציון הסיכון (יכול להיות null)
    final currentRiskColor = _riskColor(
        currentRiskScore); // צבע בהתאם לרמת הסיכון

    return Scaffold( // המסך הראשי
      backgroundColor: const Color(0xFF0F1115), // צבע רקע כהה
      appBar: AppBar( // פס עליון
        backgroundColor: const Color(0xFF0F1115),
        // אותו צבע כמו הרקע
        elevation: 0,
        // בלי צל
        scrolledUnderElevation: 0,
        // גם בגלילה אין צל
        title: const Text(
          'Safe Step', // שם האפליקציה
          style: TextStyle(
            color: Colors.white, // צבע לבן
            fontWeight: FontWeight.bold, // מודגש
            fontSize: 22, // גודל טקסט
          ),
        ),
        actions: [ // כפתורים בצד הימני של ה-AppBar
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            // רווח מהקצה (מותאם לכיוון שפה)
            child: Material( // נותן רקע ועיצוב לכפתור
              color: const Color(0xFF1B1F27), // צבע רקע לכפתור
              borderRadius: BorderRadius.circular(12), // פינות מעוגלות
              child: IconButton( // כפתור עם אייקון
                onPressed: _openSettings,
                // בלחיצה פותח את מסך ההגדרות
                icon: const Icon(
                    Icons.settings_rounded, color: Colors.white, size: 22),
                // אייקון גלגל שיניים
                padding: const EdgeInsets.all(8), // ריווח פנימי
              ),
            ),
          ),
        ],
      ),
      body: SafeArea( // מונע חפיפה עם notch/סטטוס בר
        child: SingleChildScrollView( // מאפשר גלילה אם התוכן גדול מהמסך
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // ריווח מהקצוות
          child: Column( // מסדר את רכיבי המסך בעמודה
            children: [
              _buildMainButton(buttonText),
              // כפתור הפעלה/עצירה
              const SizedBox(height: 16),
              // רווח
              _buildDangerCard(objectText, currentRiskColor),
              // כרטיס שמציג את האובייקט והסיכון
              const SizedBox(height: 16),
              // רווח
              _buildStatusRow(),
              // שורת סטטוס (מידע נוסף)
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
        // אם המערכת רצה → עוצר
        // אם לא → מפעיל

        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          // צבע רקע (כתום)
          foregroundColor: Colors.white,
          // צבע טקסט ואייקון
          elevation: 2,
          // מעט צל כדי שיבלוט (יותר נגיש)
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // פינות מעוגלות יותר
          ),
          textStyle: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // מרכז את התוכן
          children: [
            Icon(
              _isRunning
                  ? Icons.stop_circle_rounded // אם רץ → עצור
                  : Icons.play_circle_fill_rounded, // אם לא → הפעל
              size: 40,
            ),

            const SizedBox(width: 16), // רווח בין אייקון לטקסט

            Text(buttonText), // הטקסט (Start / Stop)
          ],
        ),
      ),
    );
  }

  Widget _buildDangerCard(String objectText, Color currentRiskColor) {
    // פונקציה שבונה "כרטיס סכנה" שמציג את האובייקט המסוכן ביותר והמידע עליו

    return _glassCard(
      // עטיפה בעיצוב מותאם (כנראה רקע "זכוכית"/blur שעשית במקום אחר)
      child: Column( // מסדר את כל האלמנטים אחד מתחת לשני
        children: [
          Text(
            _isHebrew ? 'האובייקט המסוכן ביותר' : 'Most dangerous object',
            // טקסט כותרת לפי שפה

            style: const TextStyle(
              fontSize: 16, // גודל קטן יחסית (כותרת משנית)
              color: Colors.white70, // לבן עם שקיפות (פחות בולט)
              fontWeight: FontWeight.w500, // חצי מודגש
            ),
          ),

          const SizedBox(height: 16), // רווח בין הכותרת לאייקון

          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            // אנימציה חלקה כשמשתנים צבע/גודל

            width: 88,
            height: 88,
            // גודל קבוע של העיגול

            decoration: BoxDecoration(
              color: currentRiskColor.withOpacity(0.14),
              // צבע רקע שקוף לפי רמת הסיכון (אדום/ירוק וכו')

              shape: BoxShape.circle, // הופך את זה לעיגול
            ),

            child: Icon(
              Icons.warning_amber_rounded, // אייקון אזהרה
              color: currentRiskColor, // צבע לפי רמת סיכון
              size: 46, // אייקון גדול וברור
            ),
          ),

          const SizedBox(height: 18), // רווח

          Text(
            objectText, // שם האובייקט (למשל "רכב")
            textAlign: TextAlign.center, // יישור למרכז

            style: const TextStyle(
              fontSize: 30, // גדול מאוד → הכי חשוב
              fontWeight: FontWeight.bold, // מודגש
              color: Colors.white, // לבן ברור
            ),
          ),

          const SizedBox(height: 18), // רווח

          if (_currentMostDangerous != null) ...[
            // אם יש אובייקט מזוהה → מציגים נתונים

            _buildMetricTile(
              title: _isHebrew ? 'רמת סיכון' : 'Risk level',
              // כותרת המדד

              value: _localizedRiskLevel(_currentMostDangerous!.riskScore),
              // המרה של מספר הסיכון לטקסט (גבוה/בינוני/נמוך)

              valueColor: currentRiskColor,
              // צבע הערך לפי רמת הסיכון

              icon: Icons.shield_rounded, // אייקון "מגן"
            ),

            const SizedBox(height: 10), // רווח בין מדדים

            _buildMetricTile(
              title: _isHebrew ? 'רמת זיהוי' : 'Detection confidence',

              value: '${(_currentMostDangerous!.confidence * 100)
                  .toStringAsFixed(0)}%',
              // הופך ערך בין 0 ל-1 לאחוזים (למשל 0.87 → 87%)

              icon: Icons.analytics_rounded, // אייקון ניתוח נתונים
            ),

            const SizedBox(height: 10),

            _buildMetricTile(
              title: _isHebrew ? 'ניקוד סיכון' : 'Risk score',

              value: _currentMostDangerous!.riskScore.toStringAsFixed(1),
              // מציג את ציון הסיכון עם ספרה אחת אחרי הנקודה

              icon: Icons.bar_chart_rounded, // אייקון גרף
            ),

          ] else
            ...[
              // אם אין אובייקט מזוהה

              Text(
                _isHebrew
                    ? 'המערכת ממתינה לזיהוי חדש.'
                    : 'The system is waiting for a new detection.',
                // הודעה למשתמש שהמערכת עדיין מחכה לזיהוי

                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
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
      // רווח פנימי בתוך הקונטיינר (ימין/שמאל 14, למעלה/למטה 10)

      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        // צבע רקע כהה (שונה מעט מהרקע הראשי)

        borderRadius: BorderRadius.circular(16),
        // פינות מעוגלות

        border: Border.all(color: Colors.white.withOpacity(0.05)),
        // מסגרת דקה מאוד עם שקיפות (כמעט לא מורגשת)
      ),

      child: Row(
        // מסדר את האלמנטים בשורה אופקית

        mainAxisAlignment: MainAxisAlignment.spaceAround,
        // מפזר את האלמנטים באופן שווה לאורך השורה

        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            // תופס רק את המקום הדרוש (ולא את כל הרוחב)

            children: [
              Icon(
                Icons.vibration,
                // אייקון שמייצג רטט

                size: 18,
                // גודל קטן יחסית

                color: _vibrationEnabled
                    ? const Color(0xFFBA68C8)
                // אם הרטט פעיל → צבע סגול בולט
                    : Colors.grey.withOpacity(0.4),
                // אם הרטט כבוי → אפור שקוף (דהוי)
              ),

              const SizedBox(width: 6),
              // רווח קטן בין האייקון לטקסט

              Text(
                _isHebrew
                    ? 'רטט: ${_vibrationEnabled ? "פעיל" : "כבוי"}'
                // בעברית: מציג אם הרטט פעיל או כבוי
                    : 'Vib: ${_vibrationEnabled ? "On" : "Off"}',
                // באנגלית: On / Off

                style: const TextStyle(fontSize: 13, color: Colors.white),
                // טקסט קטן ולבן
              ),
            ],
          ),

          Container(
            width: 1,
            height: 20,
            color: Colors.white.withOpacity(0.2),
          ),
          // קו הפרדה אנכי דק בין שני החלקים

          Row(
            mainAxisSize: MainAxisSize.min,
            // גם כאן תופס רק את הרוחב הדרוש

            children: [
              const Icon(
                Icons.language_rounded,
                size: 18,
                color: Color(0xFF64B5F6),
              ),
              // אייקון שפה (גלובוס), בצבע כחול

              const SizedBox(width: 6),
              // רווח קטן

              Text(
                _isHebrew ? 'שפה: עברית' : 'Lang: English',
                // מציג את השפה הנוכחית לפי מצב

                style: const TextStyle(fontSize: 13, color: Colors.white),
                // טקסט קטן ולבן
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    // פונקציה שבונה כרטיס מעוצב (Card) עם עיצוב אחיד
    // מקבלת Widget בשם child - זה התוכן שיופיע בתוך הכרטיס

    return Container(
      // Container = קופסה שמאפשרת שליטה על עיצוב, גודל וריווח

      padding: const EdgeInsets.all(20),
      // רווח פנימי מכל הצדדים (20 פיקסלים)
      // נותן לתוכן "מרחב נשימה" ולא צמוד לגבולות

      decoration: BoxDecoration(
        // כאן מגדירים את העיצוב של הקופסה

        color: const Color(0xFF171B22),
        // צבע רקע כהה (מתאים ל־Dark Theme)

        borderRadius: BorderRadius.circular(26),
        // פינות מעוגלות מאוד → נותן מראה מודרני ונעים

        border: Border.all(color: Colors.white.withOpacity(0.05)),
        // מסגרת דקה מאוד סביב הכרטיס
        // withOpacity(0.05) = כמעט שקוף → עדין מאוד

        boxShadow: [
          // הצללה של הכרטיס (נותן תחושת עומק)

          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            // צבע הצל (שחור עם שקיפות)

            blurRadius: 18,
            // כמה הצל מטושטש (גבוה = רך יותר)

            offset: const Offset(0, 10),
            // מיקום הצל:
            // X = 0 → אין תזוזה לצדדים
            // Y = 10 → הצל יורד למטה

          ),
        ],
      ),

      child: child,
      // כאן נכנס התוכן של הכרטיס
      // כל Widget שתעביר לפונקציה יוצג בתוך הקופסה
    );
  }

  Widget _buildMetricTile({
    required String title,
    // כותרת המדד (למשל: "רמת סיכון")

    required String value,
    // הערך של המדד (למשל: "גבוהה", "87%")

    required IconData icon,
    // האייקון שמייצג את המדד

    Color valueColor = Colors.white,
    // צבע הערך (ברירת מחדל: לבן אם לא נשלח צבע אחר)
  }) {
    return Container(
      // קופסה שמכילה את כל ה־metric (האייקון + טקסטים)

      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      // רווח פנימי: ימין/שמאל 14, למעלה/למטה 14

      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        // רקע לבן מאוד שקוף → נותן מראה עדין

        borderRadius: BorderRadius.circular(18),
        // פינות מעוגלות
      ),

      child: Row(
        // מסדר את כל האלמנטים בשורה אופקית

        children: [

          Container(
            // קופסה קטנה שמכילה את האייקון

            width: 42,
            height: 42,
            // גודל קבוע לאייקון

            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              // רקע בהיר שקוף

              borderRadius: BorderRadius.circular(14),
              // פינות מעוגלות
            ),

            child: Icon(
              icon,
              // האייקון שמגיע כפרמטר

              color: primaryColor,
              // צבע האייקון (כתום)

              size: 22,
              // גודל האייקון
            ),
          ),

          const SizedBox(width: 12),
          // רווח בין האייקון לטקסט

          Expanded(
            // גורם לטקסט לקחת את כל המקום הפנוי באמצע

            child: Text(
              title,
              // הכותרת של המדד

              style: const TextStyle(
                fontSize: 15,
                color: Colors.white70,
                // צבע בהיר אך פחות דומיננטי

                fontWeight: FontWeight.w500,
                // חצי מודגש
              ),
            ),
          ),

          Text(
            value,
            // הערך של המדד (למשל "87%" או "גבוהה")

            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              // מודגש כדי להבליט את הערך

              color: valueColor,
              // צבע דינמי (יכול להיות אדום/ירוק וכו')
            ),
          ),
        ],
      ),
    );
  }
}