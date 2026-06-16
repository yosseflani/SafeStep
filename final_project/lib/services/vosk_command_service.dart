import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

class VoskCommandService {
  static const int _sampleRate = 16000;

  static const String _modelAssetPath =
      'assets/models/vosk-model-small-en-us-0.15.zip';

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final ModelLoader _modelLoader = ModelLoader();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  StreamSubscription<String>? _resultSubscription;

  bool _isInitialized = false;
  bool _isListening = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  Future<bool> initialize() async {
    _debug('initialize()');

    try {
      final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);

      _debug('model loaded to path: $modelPath');

      _model = await _vosk.createModel(modelPath);

      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: _sampleRate,
        grammar: [
          'start',
          'stop',
          'help',
          'repeat',
          'home',
          'emergency',
          'settings',
          'yes',
          'no',
          'vibration on',
          'vibration off',
        ],
      );

      _speechService = await _vosk.initSpeechService(_recognizer!);

      _isInitialized = true;

      _debug('Vosk initialized successfully');
      return true;
    } catch (e) {
      _debug('initialize error: $e');
      return false;
    }
  }

  Future<void> startListening(Function(String command) onCommand) async {
    if (!_isInitialized || _speechService == null) {
      _debug('Vosk is not initialized');
      return;
    }

    if (_isListening) {
      _debug('already listening');
      return;
    }

    await _resultSubscription?.cancel();

    _resultSubscription = _speechService!.onResult().listen((result) {
      _debug('result: $result');

      final command = _extractCommand(result);

      if (command.isNotEmpty) {
        onCommand(command);
      }
    });

    await _speechService!.start();

    _isListening = true;

    _debug('listening started');
  }

  Future<void> stopListening() async {
    if (!_isListening || _speechService == null) return;

    await _speechService!.stop();

    await _resultSubscription?.cancel();
    _resultSubscription = null;

    _isListening = false;

    _debug('listening stopped');
  }

  Future<void> dispose() async {
    await stopListening();
  }

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

  void _debug(String msg) {
    if (!kDebugMode) return;
    debugPrint('[VoskCommandService] $msg');
  }
}