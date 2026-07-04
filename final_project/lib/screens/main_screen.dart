import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/detection.dart';
import '../services/alert_service.dart';
import '../services/camera_service.dart';
import '../services/cooldown_manager.dart';
import '../services/risk_scoring_service.dart';
import '../services/yolo_service.dart';
import '../services/vosk_command_service.dart';
import '../services/display_manager.dart';
import 'settings_screen.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';
import '../widgets/safestep_logo.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {

  // ── שירותי המערכת המרכזיים ───────────────────────────────
  final CameraService _cameraService = CameraService();
  final YoloService _yoloService = YoloService();
  final RiskScoringService _riskScoringService = RiskScoringService();
  final CooldownManager _cooldownManager = CooldownManager();
  final AlertService _alertService = AlertService();
  final DisplayManager _displayManager = DisplayManager();
  final VoskCommandService _voiceService = VoskCommandService();
  final _log = const AppLogger('SafeStep');

  // ── ניהול רטט ────────────────────────────────────────────
  DateTime? _lastVibrationTime;
  static const _vibrationCooldown = Duration(milliseconds: 500);

  // ── זיהוי תנועת משתמש באמצעות אקסלרומטר ─────────────────
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  static const _movementThreshold = 1.2;
  final List<double> _magnitudeHistory = [];
  static const _historySize = 10;

  // ── מצב ריצה ואתחול ─────────────────────────────────────
  bool _isInitialized = false;
  bool _isRunning = false;
  bool _userIsMoving = false;

  // ── הגדרות קול והתראה ───────────────────────────────────
  double _speechRate = 0.5;
  bool _vibrationEnabled = true;
  String _language = 'he-IL';

  // האובייקט המסוכן ביותר שמוצג כרגע.
  Detection? _currentMostDangerous;

  bool get _isHebrew => _language.startsWith('he');

  // ── ספי התראה לפי רמת סיכון ─────────────────────────────
  // < 20  → שקט
  // 20–30 → רטט בלבד
  // 30–65 → רטט + קול
  // 65+   → רטט + צפצוף + קול
  static const _vibrationOnlyThreshold = 20.0;
  static const _voiceAlertThreshold    = 30.0;
  static const _beepAlertThreshold     = 65.0;

  // ════════════════════════════════════════════════════════
  // INIT
  // ════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSystem();
  }

  // עוצר שירותים כשהאפליקציה עוברת לרקע.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isRunning) {
      _stopDetection();
    }
  }

  Future<void> _initializeSystem() async {
    try {
      _log.debug('System initialization started');

      // אתחול מקביל של שירותי הליבה.
      final results = await Future.wait([
        _cameraService.initialize(),
        _yoloService.initModel(),
        _voiceService.initialize(),
        _alertService.initialize(
          language: _language,
          speechRate: _speechRate,
          voiceAlertsEnabled: true,
        ),
      ]);

      final bool voiceAvailable = results[2] as bool;
      _log.debug('Voice recognition available: $voiceAvailable');

      // עדכון רזולוציית התמונה עבור חישוב סיכון מדויק.
      final controller = _cameraService.controller;
      if (controller?.value.previewSize != null) {
        _riskScoringService.updateResolution(
          controller!.value.previewSize!.width.toInt(),
          controller.value.previewSize!.height.toInt(),
        );
      }

      await _applyTtsSettings();

      if (!mounted) return;
      setState(() => _isInitialized = true);

      // מזהה האם המשתמש נמצא בתנועה.
      _accelerometerSubscription = accelerometerEventStream().listen((event) {
        final magnitude = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        _magnitudeHistory.add((magnitude - 9.8).abs());
        if (_magnitudeHistory.length > _historySize) _magnitudeHistory.removeAt(0);

        final average = _magnitudeHistory.reduce((a, b) => a + b) / _magnitudeHistory.length;
        final moving  = average > _movementThreshold;

        if (moving != _userIsMoving) setState(() => _userIsMoving = moving);
      });

      await _resumeListening();

      _log.debug('Initialization completed');
    } catch (e, stack) {
      _log.debug('Initialization failed', e, stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isHebrew ? 'שגיאה באתחול המערכת' : 'System initialization error'),
          backgroundColor: Colors.red.shade900,
          action: SnackBarAction(
            label: _isHebrew ? 'נסה שוב' : 'Retry',
            textColor: Colors.white,
            onPressed: _initializeSystem,
          ),
        ),
      );
    }
  }

  // ════════════════════════════════════════════════════════
  // TTS
  // ════════════════════════════════════════════════════════

  Future<void> _applyTtsSettings() async {
    try {
      await _alertService.updateSettings(
        language: _language,
        speechRate: _speechRate,
        voiceAlertsEnabled: true,
      );
    } catch (e) {
      _log.debug('TTS settings error', e);
    }
  }

  // ════════════════════════════════════════════════════════
  // VOICE COMMANDS
  // ════════════════════════════════════════════════════════

  Future<void> _resumeListening() async {
    if (!mounted) return;
    if (_voiceService.isListening) return;

    // מונע האזנה בזמן שהמערכת משמיעה התראה.
    while (_alertService.isSpeaking) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
    }

    await _voiceService.startListening(_handleVoiceCommand);
  }

  void _handleVoiceCommand(String command) {
    _log.debug('Voice command: "$command"');

    final text = command.toLowerCase().trim();

    // הפעלת פעולות מערכת לפי פקודות קוליות.
    if (text == 'start') {
      if (!_isRunning) {
        _startDetection();
      }
    } else if (text == 'stop') {
      if (_isRunning) {
        _stopDetection();
      }
    } else if (text == 'settings') {
      _openSettings();
    } else if (text == 'help') {
      _alertService.speakVoiceTest();
    } else if (text == 'repeat') {
      if (_currentMostDangerous != null) {
        _alertService.trySpeakDetection(_currentMostDangerous!);
      } else {
        _alertService.speakFreeText(_isHebrew ? 'אין אובייקט מסוכן כרגע' : 'No dangerous object detected');
      }
    } else if (text == 'vibration on') {
      setState(() => _vibrationEnabled = true);
    } else if (text == 'vibration off') {
      setState(() => _vibrationEnabled = false);
    }
  }

  // ════════════════════════════════════════════════════════
  // DETECTION
  // ════════════════════════════════════════════════════════

  Future<void> _startDetection() async {
    if (!_isInitialized || _isRunning) return;

    await _alertService.speakSystemStarted();
    await Future.delayed(const Duration(milliseconds: 500));

    // רטט קצר לאישור תחילת פעולה.
    if (_vibrationEnabled && await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 100);
    }

    setState(() => _isRunning = true);

    await _cameraService.startStream((CameraImage image) async {
      if (!_isRunning) return;

      try {
        // המרת פריים מהמצלמה לקלט עבור מודל הזיהוי.
        final bytesList   = image.planes.map((p) => p.bytes).toList();
        final detections  = await _yoloService.detectObjects(bytesList, image.height, image.width);

        // חישוב סיכון ובחירת האובייקט המשמעותי ביותר.
        _riskScoringService.updateResolution(image.width, image.height);
        final scored = _riskScoringService.scoreDetections(detections);
        final top    = scored.isNotEmpty ? scored.first : null;

        if (!mounted) return;

        // מעדכן תצוגה רק כשיש שינוי משמעותי.
        final shouldUpdate = _displayManager.shouldUpdateDisplay(
          hasCurrentObject: _currentMostDangerous != null,
          newRisk: top?.riskScore,
          currentRisk: _currentMostDangerous?.riskScore,
        );

        if (shouldUpdate) {
          setState(() {
            _currentMostDangerous = top;
            if (top != null) {
              _displayManager.markDisplayStart();
            } else {
              _displayManager.clearDisplayStart();
            }
          });
        }

        if (top == null) return;

        final alertLevel = _getAlertLevel(top);
        if (alertLevel == _AlertLevel.none) return;
        if (!_cooldownManager.canAlert(top.tag)) return;

        await _handleVibration(top.tag);

        if (alertLevel == _AlertLevel.vibrationOnly) {
          _cooldownManager.markAlerted(top.tag);
          return;
        }

        // עוצר האזנה כדי למנוע זיהוי שגוי של קול המערכת.
        await _voiceService.stopListening();

        if (alertLevel == _AlertLevel.beepAndVoice) {
          SystemSound.play(SystemSoundType.alert);
          await Future.delayed(const Duration(milliseconds: 300));
        }

        final spoken = await _alertService.trySpeakDetection(
          top,
          currentRisk: _currentMostDangerous?.riskScore,
        );

        if (spoken || alertLevel != _AlertLevel.none) {
          _cooldownManager.markAlerted(top.tag);
        }

        await Future.delayed(const Duration(milliseconds: 300));
        await _resumeListening();

      } catch (e, stack) {
        _log.debug('Frame processing error', e, stack);
      }
    });
  }

  _AlertLevel _getAlertLevel(Detection detection) {
    final score = detection.riskScore;

    // התראה תופעל רק אם יש תנועה יחסית.
    final relativeMotion =
        _userIsMoving || detection.isApproaching;

    if (!relativeMotion) return _AlertLevel.none;

    if (score >= _beepAlertThreshold) return _AlertLevel.beepAndVoice;
    if (score >= _voiceAlertThreshold) return _AlertLevel.voiceOnly;
    if (score >= _vibrationOnlyThreshold) return _AlertLevel.vibrationOnly;

    return _AlertLevel.none;
  }

  // ════════════════════════════════════════════════════════
  // VIBRATION
  // ════════════════════════════════════════════════════════

  Future<void> _handleVibration(String tag) async {
    if (!_vibrationEnabled) return;

    // מגביל תדירות רטט כדי למנוע עומס על המשתמש.
    final now = DateTime.now();
    if (_lastVibrationTime != null &&
        now.difference(_lastVibrationTime!) < _vibrationCooldown) {
      return;
    }

    try {
      if (!await Vibration.hasVibrator()) {
        return;
      }

      // התאמת עוצמת הרטט לסוג האובייקט.
      final duration = switch (tag) {
        'car' || 'motorcycle'                => 400,
        'pole'                               => 350,
        'person'                             => 300,
        'crosswalk'                          => 250,
        'bench' || 'couch'                   => 200,
        _                                                                   => 100,
      };

      await Vibration.vibrate(duration: duration);
      _lastVibrationTime = now;
    } catch (e) {
      _log.debug('Vibration error', e);
    }
  }

  // ════════════════════════════════════════════════════════
  // STOP
  // ════════════════════════════════════════════════════════

  Future<void> _stopDetection() async {
    if (!_isRunning) return;

    setState(() => _isRunning = false);

    // ניקוי מצב מערכת לאחר עצירת הזיהוי.
    await _cameraService.stopStream();
    await _voiceService.stopListening();
    _alertService.resetSpeakingState();
    _riskScoringService.reset();
    _cooldownManager.clear();
    _displayManager.clearDisplayStart();

    setState(() => _currentMostDangerous = null);

    await _alertService.speakSystemStopped();

    await Future.delayed(const Duration(milliseconds: 800));
    await _resumeListening();
  }

  // ════════════════════════════════════════════════════════
  // SETTINGS
  // ════════════════════════════════════════════════════════

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          speechRate: _speechRate,
          vibrationEnabled: _vibrationEnabled,
          language: _language,
          onVoiceTest: () async {
            await _applyTtsSettings();
            await _alertService.speakVoiceTest();
          },
          onChanged: (speechRate, vibrationEnabled, language) async {
            // שמירת הגדרות המשתמש ועדכון שירותי הדיבור.
            _speechRate       = speechRate;
            _vibrationEnabled = vibrationEnabled;
            _language         = language;
            await _applyTtsSettings();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }


  // ════════════════════════════════════════════════════════
  // DISPOSE
  // ════════════════════════════════════════════════════════

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // שחרור משאבים והפסקת שירותים פעילים.
    _accelerometerSubscription?.cancel();
    _cameraService.dispose();
    _yoloService.dispose();
    _alertService.stop();
    _voiceService.stopListening();
    super.dispose();
  }


  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SafeStepLogo(size: 96),
              const SizedBox(height: 28),
              const CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 18),
              Text(
                _isHebrew ? 'מאתחל את SafeStep...' : 'Initializing SafeStep...',
                style: const TextStyle(
                  color: subTextColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Container(
        // רקע הדרגתי לעיצוב מסך הבית.
        decoration: const BoxDecoration(
          gradient: backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(flex: 2),
                _buildLogoHeader(),
                const SizedBox(height: 34),
                _buildLargeStartButton(),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        const Spacer(),
        Semantics(
          button: true,
          label: _isHebrew ? 'פתח הגדרות' : 'Open settings',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _openSettings,
                  iconSize: 44,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.settings_rounded,
                    color: cardColor,
                  ),
                  tooltip: _isHebrew ? 'הגדרות' : 'Settings',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoHeader() {
    return Column(
      children: [
        const SafeStepLogo(size: 160),
        const SizedBox(height: 12),
        const Text(
          'SafeStep',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: primaryColor,
            fontSize: 38,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildLargeStartButton() {
    final isStop = _isRunning;
    final buttonColor = isStop ? dangerColor : primaryColor;

    return Semantics(
      button: true,
      label: isStop
          ? (_isHebrew ? 'עצור זיהוי מכשולים' : 'Stop obstacle detection')
          : (_isHebrew ? 'התחל זיהוי מכשולים' : 'Start obstacle detection'),
      child: GestureDetector(
        onTap: isStop ? _stopDetection : _startDetection,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: double.infinity,
          height: 250,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: buttonColor.withValues(alpha: 0.35),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isStop ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: const Color(0xFFFFF8EA),
                size: 86,
              ),
              const SizedBox(height: 18),
              Text(
                isStop
                    ? (_isHebrew ? 'עצור' : 'Stop')
                    : (_isHebrew ? 'התחל זיהוי' : 'Start Detecting'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFF8EA),
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

}


// ════════════════════════════════════════════════════════
// ENUMS
// ════════════════════════════════════════════════════════

enum _AlertLevel {
  none,           // ללא התראה.
  vibrationOnly,  // רטט בלבד.
  voiceOnly,      // התראה קולית.
  beepAndVoice,   // צפצוף והתראה קולית.
}
