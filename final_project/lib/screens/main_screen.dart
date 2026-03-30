import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

import '../models/detection.dart';
import '../services/alert_service.dart';
import '../services/camera_service.dart';
import '../services/cooldown_manager.dart';
import '../services/risk_scoring_service.dart';
import '../services/yolo_service.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

const Color primaryColor = Color(0xFFFF7A00);

class _MainScreenState extends State<MainScreen> {
  // שמרנו מופע של כל שירות של המערכת צריכה, פה יקרה התיאום בניהם
  final CameraService _cameraService = CameraService();
  final YoloService _yoloService = YoloService();
  final RiskScoringService _riskScoringService = RiskScoringService();
  final CooldownManager _cooldownManager = CooldownManager();
  final AlertService _alertService = AlertService();
  final FlutterTts _tts = FlutterTts();

  // בודק שהכל מוכן
  bool _isInitialized = false;
  bool _isRunning = false;
  bool _isDetecting = false;

  double _speechRate = 0.5;
  bool _vibrationEnabled = true;
  String _language = 'he-IL';
  String? _selectedVoice;
  List<dynamic> _voices = [];

  String _statusText = 'לחצי להתחלה';
  Detection? _currentMostDangerous;
  int _frameCounter = 0;

  @override
  // ברגע שהמסך נטען יש אתחול
  void initState() {
    super.initState();
    _initializeSystem();
  }

  // מאתחל את שלושת רכיבי המערכת העיקריים במקביל כדי לקצר זמן עלייה
  Future<void> _initializeSystem() async {
    try {
      await Future.wait([
        _cameraService.initialize(),
        _yoloService.initModel(),
        _alertService.initialize(
          language: _language,
          speechRate: _speechRate,
          voiceAlertsEnabled: true,
        ),
      ]);

      await _tts.setLanguage(_language);
      await _tts.setSpeechRate(_speechRate);
      _voices = await _tts.getVoices;

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusText = _language.startsWith('he')
            ? 'שגיאה באתחול המערכת'
            : 'System initialization error';
      });
    }
  }

  //מעדכנת את ההגדרות הרלוונטיות לקובץ alert_services ומעדכנת אותו
  Future<void> _applyTtsSettings() async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);

    if (_selectedVoice != null) {
      try {
        await _tts.setVoice({'name': _selectedVoice!});
      } catch (_) {}
    }

    await _alertService.updateSettings(
      language: _language,
      speechRate: _speechRate,
      voiceAlertsEnabled: true,
    );
  }

  // התחלת זיהוי
  Future<void> _startDetection() async {
    if (!_isInitialized || _isRunning) return;

    await _applyTtsSettings();
    await _alertService.speakSystemStarted();

    if (_vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
      Vibration.vibrate(duration: 100);
    }

    setState(() {
      _isRunning = true;
      _statusText = _language.startsWith('he')
          ? 'הזיהוי פועל כעת'
          : 'Detection is running';
    });

    // מתחיל להזרים פריימים
    await _cameraService.startStream((CameraImage image) async {
      _frameCounter++;
      if (_frameCounter % 3 != 0) return;
      if (_isDetecting) return;

      _isDetecting = true;

      try {
        final detections = await _yoloService.detectObjects(
          image.planes.map((plane) => plane.bytes).toList(),
          image.height,
          image.width,
        );

        // מחשב את הסיכון
        final scored = _riskScoringService.scoreDetections(detections);
        // לוקח את המסוכן ביותר
        final top = scored.isNotEmpty ? scored.first : null;

        if (!mounted) return;

        // מעדכן את התצוגה במסך
        setState(() {
          _currentMostDangerous = top;
          _statusText = top == null
              ? (_language.startsWith('he')
              ? 'לא זוהה אובייקט מסוכן כרגע'
              : 'No dangerous object detected right now')
              : (_language.startsWith('he')
              ? 'זוהה אובייקט הדורש תשומת לב'
              : 'An object requiring attention was detected');
        });

        // אם נמצא אובייקט מסוכן בודק האם אפשר להתריע עם קובץ cooldown_manager
        if (top != null && _cooldownManager.canAlert(top.tag)) {
          _cooldownManager.markAlerted(top.tag);
          await _applyTtsSettings();
          await _alertService.speakDetection(top);
          await _handleVibration(top.tag);
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _statusText = _language.startsWith('he')
              ? 'שגיאה בזמן זיהוי'
              : 'Detection error';
        });
      } finally {
        _isDetecting = false;
      }
    });
  }

  // פונקציה שבוחרת סוג רטט לפי סוג האובייקט - עוד דרך נוחה להבחין בניהם
  Future<void> _handleVibration(String tag) async {
    if (!_vibrationEnabled) return;
    if (!(await Vibration.hasVibrator() ?? false)) return;

    switch (tag) {
      case 'person':
        Vibration.vibrate(pattern: [0, 100]);
        break;
      case 'car':
      case 'bus':
      case 'truck':
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        break;
      case 'traffic light':
        Vibration.vibrate(pattern: [0, 50, 50, 50, 50, 50]);
        break;
      default:
        Vibration.vibrate(duration: 80);
    }
  }

  // עוצרת הזרמת פריימים
  Future<void> _stopDetection() async {
    if (!_isRunning) return;

    await _cameraService.stopStream();
    await _alertService.speakSystemStopped();

    setState(() {
      _isRunning = false;
      _currentMostDangerous = null;
      _statusText = _language.startsWith('he')
          ? 'הזיהוי הופסק'
          : 'Detection stopped';
    });
  }

  // פותחת את מסך ההגדרות
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
          onChanged: (
              double speechRate,
              bool vibrationEnabled,
              String language,
              String? selectedVoice,
              ) async {
            _speechRate = speechRate;
            _vibrationEnabled = vibrationEnabled;
            _language = language;
            _selectedVoice = selectedVoice;

            await _applyTtsSettings();

            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }

  // כל הפונקציות הבאות מחשבות את התצוגה של המסך
  String _localizedObjectName() {
    if (_currentMostDangerous == null) {
      return _language.startsWith('he')
          ? 'אין אובייקט מסוכן כרגע'
          : 'No dangerous object detected';
    }

    return _alertService.localizedLabel(_currentMostDangerous!.tag);
  }

  String _localizedRiskLevel(double riskScore) {
    if (_language.startsWith('he')) {
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

  String _systemStateText() {
    if (_language.startsWith('he')) {
      return _isRunning ? 'פעילה' : 'מושהית';
    }
    return _isRunning ? 'Active' : 'Paused';
  }

  String _languageText() {
    return _language.startsWith('he') ? 'עברית' : 'English';
  }

  String _vibrationText() {
    if (_language.startsWith('he')) {
      return _vibrationEnabled ? 'פעיל' : 'כבוי';
    }
    return _vibrationEnabled ? 'On' : 'Off';
  }

  // סוגר את שלושת הרכיבים העיקריים כשסוגרים את המסך
  @override
  void dispose() {
    _cameraService.dispose();
    _yoloService.dispose();
    _alertService.stop();
    _tts.stop();
    super.dispose();
  }

  // אם האפליקציה לא מטעינה מציג מסך loader ואם כן את המסך שלנו - פה נמצא כל העיצוב וכו
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1115),
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    final String buttonText = _isRunning
        ? (_language.startsWith('he') ? 'עצור זיהוי' : 'Stop detection')
        : (_language.startsWith('he') ? 'הפעל זיהוי' : 'Start detection');

    final String objectText = _localizedObjectName();
    final double? currentRiskScore = _currentMostDangerous?.riskScore;
    final Color currentRiskColor = _riskColor(currentRiskScore);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1115),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Vision Assistant',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Material(
              color: const Color(0xFF1B1F27),
              borderRadius: BorderRadius.circular(16),
              child: IconButton(
                onPressed: _openSettings,
                icon: const Icon(
                  Icons.settings_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 18),
            _buildSystemCard(),
            const SizedBox(height: 18),
            _buildDangerCard(objectText, currentRiskColor),
            const SizedBox(height: 18),
            _buildStatusCard(),
            const SizedBox(height: 28),
            _buildMainButton(buttonText),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF8A26),
            Color(0xFFFF6A00),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.visibility_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _language.startsWith('he')
                      ? 'עוזר ראייה חכם'
                      : 'Smart Vision Assistant',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _language.startsWith('he')
                      ? 'זיהוי מכשולים והתראות קוליות בזמן אמת.'
                      : 'Obstacle detection and real-time voice alerts.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemCard() {
    final bool isActive = _isRunning;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive
                    ? Icons.radar_rounded
                    : Icons.pause_circle_filled_rounded,
                color: isActive ? const Color(0xFF66BB6A) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                _language.startsWith('he') ? 'מצב מערכת' : 'System status',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatusChip(
                icon: isActive ? Icons.check_circle : Icons.pause_circle,
                label:
                '${_language.startsWith('he') ? 'סטטוס' : 'Status'}: ${_systemStateText()}',
                color: isActive ? const Color(0xFF66BB6A) : Colors.grey,
              ),
              _buildStatusChip(
                icon: Icons.language_rounded,
                label:
                '${_language.startsWith('he') ? 'שפה' : 'Language'}: ${_languageText()}',
                color: const Color(0xFF64B5F6),
              ),
              _buildStatusChip(
                icon: Icons.vibration_rounded,
                label:
                '${_language.startsWith('he') ? 'רטט' : 'Vibration'}: ${_vibrationText()}',
                color: const Color(0xFFBA68C8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDangerCard(String objectText, Color currentRiskColor) {
    return _glassCard(
      child: Column(
        children: [
          Text(
            _language.startsWith('he')
                ? 'האובייקט המסוכן ביותר'
                : 'Most dangerous object',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: currentRiskColor.withOpacity(0.14),
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
            _buildMetricTile(
              title: _language.startsWith('he') ? 'רמת סיכון' : 'Risk level',
              value: _localizedRiskLevel(_currentMostDangerous!.riskScore),
              valueColor: currentRiskColor,
              icon: Icons.shield_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricTile(
              title:
              _language.startsWith('he') ? 'רמת זיהוי' : 'Detection confidence',
              value:
              '${(_currentMostDangerous!.confidence * 100).toStringAsFixed(0)}%',
              icon: Icons.analytics_rounded,
            ),
            const SizedBox(height: 10),
            _buildMetricTile(
              title: _language.startsWith('he') ? 'ניקוד סיכון' : 'Risk score',
              value: _currentMostDangerous!.riskScore.toStringAsFixed(1),
              icon: Icons.bar_chart_rounded,
            ),
          ] else ...[
            Text(
              _language.startsWith('he')
                  ? 'המערכת ממתינה לזיהוי חדש.'
                  : 'The system is waiting for a new detection.',
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

  Widget _buildStatusCard() {
    return _glassCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _statusText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainButton(String buttonText) {
    return SizedBox(
      width: double.infinity,
      height: 72,
      child: ElevatedButton(
        onPressed: _isRunning ? _stopDetection : _startDetection,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: const TextStyle(
            fontSize: 23,
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
            ),
            const SizedBox(width: 10),
            Text(buttonText),
          ],
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryColor, size: 22),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}