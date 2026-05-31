import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'dart:math';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/detection.dart';
import '../services/alert_service.dart';
import '../services/camera_service.dart';
import '../services/cooldown_manager.dart';
import '../services/risk_scoring_service.dart';
import '../services/yolo_service.dart';
import 'display_manager.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

const Color primaryColor = Color(0xFFFF7A00);

class _MainScreenState extends State<MainScreen> {
  final CameraService _cameraService = CameraService();
  final YoloService _yoloService = YoloService();
  final RiskScoringService _riskScoringService = RiskScoringService();
  final CooldownManager _cooldownManager = CooldownManager();
  final AlertService _alertService = AlertService();
  final FlutterTts _tts = FlutterTts();
  final DisplayManager _displayManager = DisplayManager();
  final AudioPlayer _player = AudioPlayer();

  bool _isProcessingFrame = false;

  // 🔍 לוגים ממוקדים ל-Debug
  void _debug(String message, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    final time = DateTime.now().toIso8601String().split('T').last.split('.').first;
    debugPrint('[SafeStep][$time] $message');
    if (error != null) debugPrint('[SafeStep][$time][ERROR] $error');
    if (stackTrace != null && kDebugMode) debugPrint('[SafeStep][$time][STACK] $stackTrace');
  }

  // 📳 רטט
  DateTime? _lastVibrationTime;
  static const _vibrationCooldown = Duration(milliseconds: 500);

  // 📊 אקסלרומטר לזיהוי תנועה
  StreamSubscription? _accelerometerSubscription;
  static const _movementThreshold = 1.2;
  final List<double> _magnitudeHistory = [];
  static const _historySize = 10;

  // 🎛️ מצב מערכת
  bool _isInitialized = false;
  bool _isRunning = false;
  bool _userIsMoving = false;

  // ⚙️ הגדרות משתמש
  double _speechRate = 0.5;
  bool _vibrationEnabled = true;
  String _language = 'he-IL';
  String? _selectedVoice;
  List<Map<String, dynamic>> _voices = [];

  Detection? _currentMostDangerous;
  bool get _isHebrew => _language.startsWith('he');

  // 🚨 ספי התראה
  static const _vibrationOnlyThreshold = 30.0;
  static const _voiceAlertThreshold = 40.0;
  static const _beepAlertThreshold = 65.0;

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    try {
      _debug('System initialization started');

      await Future.wait([
        _cameraService.initialize(),
        _yoloService.initModel(),
        _alertService.initialize(
          language: _language,
          speechRate: _speechRate,
          voiceAlertsEnabled: true,
        ),
      ]);

      final controller = _cameraService.controller;
      if (controller?.value.previewSize != null) {
        _riskScoringService.updateResolution(
          controller!.value.previewSize!.width.toInt(),
          controller.value.previewSize!.height.toInt(),
        );
      }

      final raw = await _tts.getVoices ?? [];
      _voices = raw.whereType<Map<String, dynamic>>().toList();
      await _applyTtsSettings();

      if (!mounted) return;
      setState(() => _isInitialized = true);

      // 📊 האזנה לאקסלרומטר
      _accelerometerSubscription = accelerometerEvents.listen((event) {
        final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        _magnitudeHistory.add((magnitude - 9.8).abs());
        if (_magnitudeHistory.length > _historySize) _magnitudeHistory.removeAt(0);

        final average = _magnitudeHistory.reduce((a, b) => a + b) / _magnitudeHistory.length;
        final moving = average > _movementThreshold;

        if (moving != _userIsMoving) {
          setState(() => _userIsMoving = moving);
        }
      });

      _debug('✅ Initialization completed');
    } catch (e, stack) {
      _debug('❌ Initialization failed', e, stack);
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

  Future<void> _applyTtsSettings() async {
    try {
      await _tts.setLanguage(_language);
      await _tts.setSpeechRate(_speechRate.clamp(0.1, 2.0));
      if (_selectedVoice != null) await _tts.setVoice({'name': _selectedVoice!});
      await _alertService.updateSettings(
        language: _language,
        speechRate: _speechRate,
        voiceAlertsEnabled: true,
      );
    } catch (e) {
      _debug('TTS settings error', e);
    }
  }

  Future<void> _startDetection() async {
    if (!_isInitialized || _isRunning) return;

    await _alertService.speakSystemStarted();
    await Future.delayed(const Duration(milliseconds: 500));

    if (_vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
      await Vibration.vibrate(duration: 100);
    }

    setState(() => _isRunning = true);

    await _cameraService.startStream((CameraImage image) async {
      if (!_isRunning || _isProcessingFrame) return;
      _isProcessingFrame = true;

      try {
        final bytesList = image.planes.map((plane) => plane.bytes).toList();
        final detections = await _yoloService.detectObjects(bytesList, image.height, image.width);

        _riskScoringService.updateResolution(image.width, image.height);
        final scored = _riskScoringService.scoreDetections(detections);
        final top = scored.isNotEmpty ? scored.first : null;

        if (!mounted) return;

        // 🖥️ עדכון תצוגה חכם
        final shouldUpdateDisplay = _displayManager.shouldUpdateDisplay(
          hasCurrentObject: _currentMostDangerous != null,
          newRisk: top?.riskScore,
          currentRisk: _currentMostDangerous?.riskScore,
        );

        if (shouldUpdateDisplay) {
          setState(() {
            _currentMostDangerous = top;
            if (top != null) _displayManager.markDisplayStart();
            else _displayManager.clearDisplayStart();
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

        if (alertLevel == _AlertLevel.beepAndVoice) {
          await _player.play(AssetSource('beep.mp3'));
          await Future.delayed(const Duration(milliseconds: 250));
        }

        final spoken = await _alertService.trySpeakDetection(top, currentRisk: _currentMostDangerous?.riskScore);
        if (spoken || alertLevel == _AlertLevel.voiceOnly || alertLevel == _AlertLevel.beepAndVoice) {
          _cooldownManager.markAlerted(top.tag);
        }

      } catch (e, stack) {
        _debug('Frame processing error', e, stack);
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  /// מחזיר רמת התראה לפי ציון הסיכון בלבד (לפי הטבלה המבוקשת)
  _AlertLevel _getAlertLevel(Detection detection) {
    final double riskScore = detection.riskScore;

    // 🟢 0–30: ללא התראה
    if (riskScore < 30.0) {
      return _AlertLevel.none;
    }

    // 🟡 30–40: רטט בלבד
    if (riskScore < 40.0) {
      return _AlertLevel.vibrationOnly;
    }

    // 🟠 40–65: רטט + קול
    if (riskScore < 65.0) {
      return _AlertLevel.voiceOnly;
    }

    // 🔴 65+: רטט + צפצוף + קול
    return _AlertLevel.beepAndVoice;
  }

  Future<void> _handleVibration(String tag) async {
    if (!_vibrationEnabled) return;
    final now = DateTime.now();
    if (_lastVibrationTime != null && now.difference(_lastVibrationTime!) < _vibrationCooldown) return;

    try {
      if (!(await Vibration.hasVibrator() ?? false)) return;

      int duration;
      switch (tag) {
        case 'car': case 'bus': case 'truck': case 'train': case 'motorcycle':
        duration = 400; break;
        case 'person': case 'bicycle': case 'scooter': case 'skateboard':
        duration = 250; break;
        case 'traffic light': case 'stop sign': case 'fire hydrant': case 'crosswalk':
        duration = 150; break;
        case 'dog': case 'cat': case 'horse': case 'sheep': case 'cow':
        case 'elephant': case 'bear': case 'zebra': case 'giraffe': case 'bird':
        duration = 200; break;
        case 'bench': case 'chair': case 'couch': case 'bed':
        case 'dining table': case 'potted plant':
        duration = 300; break;
        case 'backpack': case 'handbag': case 'suitcase': case 'umbrella':
        duration = 180; break;
        case 'skis': case 'sports ball': case 'surfboard': case 'tennis racket':
        duration = 120; break;
        default: duration = 100;
      }

      await Vibration.vibrate(duration: duration);
      _lastVibrationTime = now;
    } catch (e) {
      _debug('Vibration error', e);
    }
  }

  Future<void> _stopDetection() async {
    if (!_isRunning) return;
    setState(() => _isRunning = false);

    await _cameraService.stopStream();
    await _player.stop();
    await _alertService.stop();
    _riskScoringService.reset();
    _cooldownManager.clear();
    _displayManager.clearDisplayStart();

    setState(() => _currentMostDangerous = null);
    await _alertService.speakSystemStopped();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          speechRate: _speechRate,
          vibrationEnabled: _vibrationEnabled,
          language: _language,
          voices: _voices,
          selectedVoice: _selectedVoice,
          onVoiceTest: () async {
            await _applyTtsSettings();
            await _alertService.speakVoiceTest();
          },
          onChanged: (speechRate, vibrationEnabled, language, selectedVoice) async {
            _speechRate = speechRate;
            _vibrationEnabled = vibrationEnabled;
            _language = language;
            _selectedVoice = selectedVoice;
            await _applyTtsSettings();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  String _localizedObjectName() {
    if (_currentMostDangerous == null) {
      return _isHebrew ? 'אין אובייקט מסוכן כרגע' : 'No dangerous object detected';
    }
    return _alertService.localizedLabel(_currentMostDangerous!.tag);
  }

  String _localizedRiskLevel(double riskScore) {
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
    if (riskScore == null) return Colors.grey;
    if (riskScore >= 75) return const Color(0xFFFF5A5F);
    if (riskScore >= 50) return const Color(0xFFFFA726);
    return const Color(0xFF66BB6A);
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _cameraService.dispose();
    _yoloService.dispose();
    _alertService.stop();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              Text(_isHebrew ? 'מאתחל מערכת...' : 'Initializing...',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    final buttonText = _isRunning
        ? (_isHebrew ? 'עצור זיהוי' : 'Stop')
        : (_isHebrew ? 'הפעל זיהוי' : 'Start');
    final objectText = _localizedObjectName();
    final currentRiskScore = _currentMostDangerous?.riskScore;
    final currentRiskColor = _riskColor(currentRiskScore);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1115),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Safe Step',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Material(
              color: const Color(0xFF1B1F27),
              borderRadius: BorderRadius.circular(12),
              child: IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              _buildMainButton(buttonText),
              const SizedBox(height: 16),
              _buildDangerCard(objectText, currentRiskColor),
              const SizedBox(height: 16),
              _buildStatusRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton(String buttonText) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: ElevatedButton(
        onPressed: _isRunning ? _stopDetection : _startDetection,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_isRunning ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, size: 40),
            const SizedBox(width: 16),
            Text(buttonText),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerCard(String objectText, Color currentRiskColor) {
    return _glassCard(
      child: Column(
        children: [
          Text(_isHebrew ? 'האובייקט המסוכן ביותר' : 'Most dangerous object',
              style: const TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: currentRiskColor.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: currentRiskColor, size: 46),
          ),
          const SizedBox(height: 18),
          Text(objectText, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 18),
          if (_currentMostDangerous != null) ...[
            _buildMetricTile(title: _isHebrew ? 'רמת סיכון' : 'Risk level',
                value: _localizedRiskLevel(_currentMostDangerous!.riskScore),
                valueColor: currentRiskColor, icon: Icons.shield_rounded),
            const SizedBox(height: 10),
            _buildMetricTile(title: _isHebrew ? 'רמת זיהוי' : 'Detection confidence',
                value: '${(_currentMostDangerous!.confidence * 100).toStringAsFixed(0)}%',
                icon: Icons.analytics_rounded),
            const SizedBox(height: 10),
            _buildMetricTile(title: _isHebrew ? 'ניקוד סיכון' : 'Risk score',
                value: _currentMostDangerous!.riskScore.toStringAsFixed(1),
                icon: Icons.bar_chart_rounded),
          ] else ...[
            Text(_isHebrew ? 'המערכת ממתינה לזיהוי חדש.' : 'The system is waiting for a new detection.',
                style: const TextStyle(fontSize: 15, color: Colors.white70)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.vibration, size: 18,
                color: _vibrationEnabled ? const Color(0xFFBA68C8) : Colors.grey.withOpacity(0.4)),
            const SizedBox(width: 6),
            Text(_isHebrew ? 'רטט: ${_vibrationEnabled ? "פעיל" : "כבוי"}' : 'Vib: ${_vibrationEnabled ? "On" : "Off"}',
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ]),
          Container(width: 1, height: 20, color: Colors.white.withOpacity(0.2)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.language_rounded, size: 18, color: Color(0xFF64B5F6)),
            const SizedBox(width: 6),
            Text(_isHebrew ? 'שפה: עברית' : 'Lang: English',
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ]),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    Color valueColor = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.w500))),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }
}

enum _AlertLevel { none, vibrationOnly, voiceOnly, beepAndVoice }