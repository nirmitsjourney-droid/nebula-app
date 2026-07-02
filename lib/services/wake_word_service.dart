import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class WakeWordService extends ChangeNotifier {
  stt.SpeechToText? _speech;
  bool _initialized = false;
  bool _isListening = false;
  bool _enabled = false;

  static const String _wakeWord = 'nebula';

  bool get enabled => _enabled;
  bool get isListening => _isListening;

  VoidCallback? onWakeWordDetected;

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();

    if (value) {
      await _tryStartListening();
    } else {
      await _stopListening();
    }
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _speech ??= stt.SpeechToText();
    try {
      _initialized = await _speech!.initialize(
        onError: (val) => debugPrint('[WakeWord] STT Error: $val'),
        onStatus: (val) {
          debugPrint('[WakeWord] Status: $val');
          if (val == 'notListening' || val == 'done') {
            if (_enabled && _isListening) {
              _restartListening();
            }
          }
        },
      );
      return _initialized;
    } catch (e) {
      debugPrint('[WakeWord] Init failed: $e');
      _initialized = false;
      return false;
    }
  }

  Future<void> _tryStartListening() async {
    final ready = await _ensureInitialized();
    if (!ready) return;

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint('[WakeWord] Microphone permission denied');
      return;
    }

    if (_speech != null && !_speech!.isListening) {
      _isListening = true;
      notifyListeners();

      try {
        await _speech!.listen(
          onResult: (result) {
            final words = result.recognizedWords.toLowerCase();
            if (words.contains(_wakeWord)) {
              _onWakeWord();
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenFor: const Duration(hours: 24),
            pauseFor: const Duration(seconds: 5),
            partialResults: true,
            localeId: 'en_US',
          ),
        );
      } catch (e) {
        debugPrint('[WakeWord] Listen failed: $e');
        _isListening = false;
        notifyListeners();
      }
    }
  }

  Future<void> _stopListening() async {
    if (_speech != null && _speech!.isListening) {
      try {
        await _speech!.stop();
      } catch (e) {
        debugPrint('[WakeWord] Stop failed: $e');
      }
    }
    _isListening = false;
    notifyListeners();
  }

  void _onWakeWord() {
    debugPrint('[WakeWord] Wake word "Nebula" detected!');
    _onWakeWordAsync();
  }

  Future<void> _onWakeWordAsync() async {
    try {
      if (_speech != null && _speech!.isListening) {
        await _speech!.stop();
      }
      _isListening = false;
      notifyListeners();
      onWakeWordDetected?.call();
    } catch (e) {
      debugPrint('[WakeWord] Error during wake word handling: $e');
    }

    if (_enabled) {
      await Future.delayed(const Duration(seconds: 2));
      await _tryStartListening();
    }
  }

  void _restartListening() {
    if (!_enabled) return;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_enabled) _tryStartListening();
    });
  }

  @override
  void dispose() {
    _speech?.stop();
    super.dispose();
  }
}
