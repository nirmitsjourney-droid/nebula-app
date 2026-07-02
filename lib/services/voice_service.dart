import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum VoiceState { idle, listeningUser, speakingAI }

class VoiceService extends ChangeNotifier {
  stt.SpeechToText? _speech;
  bool _speechInitialized = false;
  String _transcript = '';
  String get transcript => _transcript;

  final FlutterTts _tts = FlutterTts();
  bool _ttsInitialized = false;
  bool _ttsSpeaking = false;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  static const int barCount = 16;
  List<double> _amplitudes = List.filled(barCount, 0.05);
  List<double> get amplitudes => List.unmodifiable(_amplitudes);

  ValueChanged<String>? onTranscriptReady;
  ValueChanged<String>? onTranscriptUpdate;

  Timer? _ttsVisualizerTimer;
  final Random _random = Random();

  // ── Lazy TTS Init ────────────────────────────────────────────────────────

  Future<bool> _ensureTts() async {
    if (_ttsInitialized) return true;
    try {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(() {
        _ttsSpeaking = true;
        _state = VoiceState.speakingAI;
        _startTtsVisualizerAnimation();
        notifyListeners();
      });

      _tts.setCompletionHandler(() {
        _ttsSpeaking = false;
        _state = VoiceState.idle;
        _stopTtsVisualizerAnimation();
        _resetAmplitudes();
        notifyListeners();
      });

      _tts.setErrorHandler((msg) {
        debugPrint('[VoiceService TTS Error] $msg');
        _ttsSpeaking = false;
        _state = VoiceState.idle;
        _stopTtsVisualizerAnimation();
        _resetAmplitudes();
        notifyListeners();
      });

      _ttsInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[VoiceService TTS Init Failed] $e');
      return false;
    }
  }

  // ── Lazy STT Init ────────────────────────────────────────────────────────

  Future<bool> _ensureSpeech() async {
    if (_speechInitialized) return true;
    _speech ??= stt.SpeechToText();
    try {
      _speechInitialized = await _speech!.initialize(
        onError: (val) => debugPrint('[VoiceService STT Error] $val'),
        onStatus: (val) {
          debugPrint('[VoiceService STT Status] $val');
          if (val == 'notListening' || val == 'done') {
            if (_state == VoiceState.listeningUser) {
              stopListening();
            }
          }
        },
      );
      return _speechInitialized;
    } catch (e) {
      debugPrint('[VoiceService STT Init Failed] $e');
      _speechInitialized = false;
      return false;
    }
  }

  // ── STT Control ────────────────────────────────────────────────────────

  Future<void> startListening() async {
    final ready = await _ensureSpeech();
    if (!ready) {
      debugPrint('[VoiceService] STT not available');
      return;
    }

    if (_ttsSpeaking) {
      await stopSpeaking();
    }

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint('[VoiceService] Microphone permission not granted');
      return;
    }

    if (_speech != null && !_speech!.isListening) {
      _transcript = '';
      _state = VoiceState.listeningUser;
      notifyListeners();

      try {
        await _speech!.listen(
          onResult: (result) {
            _transcript = result.recognizedWords;
            onTranscriptUpdate?.call(_transcript);
            if (result.finalResult) {
              final text = _transcript;
              stopListening();
              onTranscriptReady?.call(text);
            }
          },
          onSoundLevelChange: (double level) {
            final normalized = ((level + 2) / 12.0).clamp(0.1, 1.0);
            _updateAmplitudesWithInput(normalized);
          },
          listenOptions: stt.SpeechListenOptions(
            listenFor: const Duration(seconds: 30),
            pauseFor: const Duration(seconds: 2),
            partialResults: true,
          ),
        );
      } catch (e) {
        debugPrint('[VoiceService] Listen failed: $e');
        _state = VoiceState.idle;
        notifyListeners();
      }
    }
  }

  Future<void> stopListening() async {
    if (_speech != null && _speech!.isListening) {
      try {
        await _speech!.stop();
      } catch (e) {
        debugPrint('[VoiceService] Stop failed: $e');
      }
    }
    _state = VoiceState.idle;
    _resetAmplitudes();
    notifyListeners();
  }

  // ── TTS Control ────────────────────────────────────────────────────────

  Future<void> speak(String text) async {
    final ready = await _ensureTts();
    if (!ready) return;

    if (_speech != null && _speech!.isListening) {
      await stopListening();
    }

    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[VoiceService] Speak failed: $e');
    }
  }

  Future<void> stopSpeaking() async {
    if (_ttsSpeaking) {
      try {
        await _tts.stop();
      } catch (e) {
        debugPrint('[VoiceService] Stop speaking failed: $e');
      }
      _ttsSpeaking = false;
      _state = VoiceState.idle;
      _stopTtsVisualizerAnimation();
      _resetAmplitudes();
      notifyListeners();
    }
  }

  // ── Audio Visualizer ───────────────────────────────────────────────────

  void _updateAmplitudesWithInput(double peak) {
    for (int i = 0; i < barCount; i++) {
      final multiplier = 0.4 + 0.6 * sin((i / (barCount - 1)) * pi);
      final noise = (_random.nextDouble() - 0.5) * 0.15;
      _amplitudes[i] = (peak * multiplier + noise).clamp(0.08, 1.0);
    }
    notifyListeners();
  }

  void _startTtsVisualizerAnimation() {
    _ttsVisualizerTimer?.cancel();
    _ttsVisualizerTimer = Timer.periodic(const Duration(milliseconds: 70), (timer) {
      final time = DateTime.now().millisecondsSinceEpoch / 250.0;
      final envelope = 0.3 + 0.5 * (sin(time) * cos(time * 0.7)).abs();

      for (int i = 0; i < barCount; i++) {
        final distFromCenter = (i - barCount / 2).abs() / (barCount / 2);
        final weight = 1.0 - distFromCenter * 0.6;
        final wave = 0.1 + 0.9 * sin(time + i * 0.45).abs();
        _amplitudes[i] = (wave * envelope * weight).clamp(0.08, 1.0);
      }
      notifyListeners();
    });
  }

  void _stopTtsVisualizerAnimation() {
    _ttsVisualizerTimer?.cancel();
    _ttsVisualizerTimer = null;
  }

  void _resetAmplitudes() {
    _amplitudes = List.filled(barCount, 0.05);
  }

  @override
  void dispose() {
    _stopTtsVisualizerAnimation();
    _speech?.stop();
    _tts.stop();
    super.dispose();
  }
}
