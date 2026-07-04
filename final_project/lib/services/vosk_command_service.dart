import 'dart:async';
import 'dart:convert';

import 'package:vosk_flutter/vosk_flutter.dart';

import '../utils/logger.dart';

/// שירות לזיהוי פקודות קוליות באמצעות Vosk.
class VoskCommandService {
  final _log = const AppLogger('VoskCommand');
  // קצב הדגימה הנדרש למודל הזיהוי.
  static const int _sampleRate = 16000;

  // נתיב מודל Vosk מתוך תיקיית assets.
  static const String _modelAssetPath =
      'assets/models/vosk-model-small-en-us-0.15.zip';

  // מופעי Vosk לניהול המודל והזיהוי הקולי.
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final ModelLoader _modelLoader = ModelLoader();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  // מנוי לתוצאות הזיהוי מה־Stream.
  StreamSubscription<String>? _resultSubscription;

  bool _isInitialized = false;
  bool _isListening = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  /// טוען את מודל Vosk ומכין את שירות הזיהוי.
  Future<bool> initialize() async {
    _log.debug('initialize()');

    try {
      final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);

      _model = await _vosk.createModel(modelPath);

      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: _sampleRate,

        // הגבלת הזיהוי לפקודות הרלוונטיות לאפליקציה.
        grammar: [
          'start',
          'stop',
          'help',
          'repeat',
          'settings',
          'vibration on',
          'vibration off',
        ],
      );

      _speechService = await _vosk.initSpeechService(_recognizer!);

      _isInitialized = true;

      _log.debug('Vosk initialized successfully');
      return true;
    } catch (e) {
      _log.debug('initialize error: $e');
      return false;
    }
  }

  /// מתחיל האזנה לפקודות קוליות.
  Future<void> startListening(Function(String command) onCommand) async {
    if (!_isInitialized || _speechService == null) {
      _log.debug('Vosk is not initialized');
      return;
    }

    if (_isListening) {
      _log.debug('already listening');
      return;
    }

    // ביטול מנוי קודם לפני פתיחת האזנה חדשה.
    await _resultSubscription?.cancel();

    _resultSubscription = _speechService!.onResult().listen((result) {
      final command = _extractCommand(result);

      if (command.isNotEmpty) {
        onCommand(command);
      }
    });

    await _speechService!.start();

    _isListening = true;

    _log.debug('listening started');
  }

  /// עוצר את ההאזנה ומשחרר את מנוי התוצאות.
  Future<void> stopListening() async {
    if (!_isListening || _speechService == null) return;

    await _speechService!.stop();

    await _resultSubscription?.cancel();
    _resultSubscription = null;

    _isListening = false;

    _log.debug('listening stopped');
  }

  /// מנקה משאבי האזנה פעילים.
  Future<void> dispose() async {
    await stopListening();
  }

  /// מחלץ את טקסט הפקודה מתוך תוצאת JSON של Vosk.
  String _extractCommand(String result) {
    try {
      final json = jsonDecode(result);

      final text = json['text'];

      if (text is String) {
        return text.trim().toLowerCase();
      }

      return '';
    } catch (_) {
      return '';
    }
  }

}