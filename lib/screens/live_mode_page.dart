import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../services/openai_service.dart';
import '../services/voice_service.dart';

class LiveModePage extends StatefulWidget {
  const LiveModePage({
    super.key,
    required this.openAIService,
    required this.voiceService,
    required this.onClose,
  });

  final OpenAIService openAIService;
  final VoiceService voiceService;
  final VoidCallback onClose;

  @override
  State<LiveModePage> createState() => _LiveModePageState();
}

class _LiveModePageState extends State<LiveModePage>
    with SingleTickerProviderStateMixin {
  final List<_LiveMessage> _messages = [];
  CameraController? _cameraController;
  bool _cameraReady = false;
  String _streamingText = '';
  bool _isStreaming = false;
  bool _isListening = false;
  bool _cameraInitializing = true;
  bool _cameraFailed = false;

  StreamSubscription<String>? _streamSub;

  late final AnimationController _orbCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.0, end: 1.0).animate(_orbCtrl);

    widget.voiceService.onTranscriptReady = _onVoiceResult;
    widget.voiceService.addListener(_onVoiceStateChanged);

    _initCamera();
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    _streamSub?.cancel();
    widget.voiceService.onTranscriptReady = null;
    widget.voiceService.removeListener(_onVoiceStateChanged);
    widget.voiceService.stopListening();
    widget.voiceService.stopSpeaking();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    setState(() {
      _cameraInitializing = true;
      _cameraFailed = false;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraInitializing = false;
          _cameraFailed = true;
        });
        return;
      }
      final controller = CameraController(cameras.first, ResolutionPreset.medium);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _cameraInitializing = false;
      });
    } catch (e) {
      debugPrint('[LiveMode] Camera init failed: $e');
      if (mounted) setState(() {
        _cameraInitializing = false;
        _cameraFailed = true;
      });
    }
  }

  void _onVoiceStateChanged() {
    if (mounted) {
      setState(() {
        _isListening = widget.voiceService.state == VoiceState.listeningUser;
      });
    }
  }

  void _onVoiceResult(String text) {
    if (text.trim().isEmpty) return;
    _sendToAI(text.trim());
  }

  Future<File?> _captureFromCamera() async {
    if (_cameraController != null && _cameraReady) {
      try {
        final image = await _cameraController!.takePicture();
        return File(image.path);
      } catch (e) {
        debugPrint('[LiveMode] Camera capture failed: $e');
      }
    }
    return null;
  }

  Future<void> _captureAndSend() async {
    final photo = await _captureFromCamera();
    if (photo == null) return;
    if (!mounted) return;

    final messages = List<ChatMessage>.from(_messages.map((m) =>
      ChatMessage(id: 'hist_${m.hashCode}', text: m.text, isUser: m.isUser)));

    setState(() {
      _messages.add(_LiveMessage(text: '[Took a photo]', isUser: true));
      _streamingText = '';
      _isStreaming = true;
    });

    final userMsg = ChatMessage(
      id: 'live_photo', text: 'What do you see in this photo?', isUser: true,
      imagePath: photo.path,
    );
    messages.add(userMsg);

    _startStream(messages);
  }

  void _toggleMic() {
    if (_isListening) {
      widget.voiceService.stopListening();
    } else {
      widget.voiceService.startListening();
    }
  }

  void _sendToAI(String text) {
    if (_isStreaming) return;
    setState(() {
      _messages.add(_LiveMessage(text: text, isUser: true));
      _streamingText = '';
      _isStreaming = true;
    });
    _doSendToAI(text);
  }

  Future<void> _doSendToAI(String text) async {
    final messages = List<ChatMessage>.from(_messages
        .take(_messages.length - 1)
        .map((m) => ChatMessage(id: 'hist_${m.hashCode}', text: m.text, isUser: m.isUser)));

    messages.add(ChatMessage(id: 'live_in', text: text, isUser: true));
    _startStream(messages);
  }

  void _startStream(List<ChatMessage> messages) {
    _streamSub?.cancel();

    try {
      final stream = widget.openAIService.streamChatCompletion(messages);
      String accumulated = '';

      _streamSub = stream.listen(
        (chunk) {
          if (!mounted) return;
          accumulated += chunk;
          setState(() => _streamingText = accumulated);
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            if (accumulated.isNotEmpty) {
              _messages.add(_LiveMessage(text: accumulated, isUser: false));
            }
            _streamingText = '';
            _isStreaming = false;
          });
          if (accumulated.isNotEmpty) {
            widget.voiceService.speak(accumulated).then((_) {
              if (mounted) widget.voiceService.startListening();
            });
          } else {
            if (mounted) widget.voiceService.startListening();
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _messages.add(_LiveMessage(text: 'Error: $e', isUser: false));
            _streamingText = '';
            _isStreaming = false;
          });
          if (mounted) widget.voiceService.startListening();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_LiveMessage(text: 'Connection error: $e', isUser: false));
        _isStreaming = false;
      });
      if (mounted) widget.voiceService.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(colors),
            _buildCameraPreview(colors),
            Expanded(child: _buildConversation(colors)),
            _buildControls(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colors) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: colors.surfaceContainerHigh,
              ),
              child: Icon(Icons.close_rounded, size: 18, color: colors.onSurface),
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.videocam_rounded, size: 18, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            'Live Mode',
            style: TextStyle(
              color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_isStreaming)
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview(ColorScheme colors) {
    if (_cameraInitializing) {
      return Container(
        height: 200,
        color: colors.surfaceContainer,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_cameraFailed) {
      return GestureDetector(
        onTap: _initCamera,
        child: Container(
          height: 200,
          color: colors.surfaceContainer,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_rounded, size: 32, color: colors.onSurfaceVariant),
                const SizedBox(height: 6),
                Text('Camera unavailable', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: colors.surfaceContainerHigh,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text('Tap to retry', style: TextStyle(color: colors.primary, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return Container(
        height: 200,
        color: colors.surfaceContainer,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded, size: 32, color: colors.onSurfaceVariant),
              const SizedBox(height: 6),
              Text('No camera detected', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Stack(
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: CameraPreview(_cameraController!),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: GestureDetector(
              onTap: _captureAndSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.9),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(Icons.camera_alt_rounded, size: 20, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation(ColorScheme colors) {
    if (_messages.isEmpty && !_isStreaming) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildOrb(colors),
            const SizedBox(height: 16),
            Text(
              'Tap the mic and speak',
              style: TextStyle(
                color: colors.onSurface, fontSize: 17, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use the camera to show what you see',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      itemCount: _messages.length + (_isStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isStreaming && _streamingText.isNotEmpty) {
          return _LiveBubble(text: _streamingText, isUser: false, isStreaming: true);
        }
        if (index == _messages.length && _isStreaming) {
          return const _LiveTypingIndicator();
        }
        final msg = _messages[index];
        return _LiveBubble(text: msg.text, isUser: msg.isUser);
      },
    );
  }

  Widget _buildControls(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _toggleMic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? colors.primary : colors.surfaceContainerHigh,
                border: Border.all(
                  color: _isListening ? colors.primary : colors.outlineVariant,
                  width: 2,
                ),
                boxShadow: _isListening
                    ? [BoxShadow(color: colors.primary.withValues(alpha: 0.3), blurRadius: 12)]
                    : null,
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none_rounded,
                size: 26,
                color: _isListening ? colors.onPrimary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(ColorScheme colors) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        final scale = 1.0 + _pulseAnim.value * 0.15;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.3),
                  blurRadius: 16 + _pulseAnim.value * 8,
                  spreadRadius: 2 + _pulseAnim.value * 4,
                ),
              ],
            ),
            child: Icon(Icons.auto_awesome, size: 30, color: colors.onPrimary),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _LiveMessage {
  _LiveMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

// ═══════════════════════════════════════════════════════════════════════════

class _LiveBubble extends StatelessWidget {
  const _LiveBubble({required this.text, required this.isUser, this.isStreaming = false});
  final String text;
  final bool isUser;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: Border.all(color: isUser ? colors.primary : colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isUser ? colors.onPrimaryContainer : colors.onSurface,
                fontSize: 13, height: 1.45,
              ),
            ),
            if (isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _LiveTypingIndicator extends StatefulWidget {
  const _LiveTypingIndicator();

  @override
  State<_LiveTypingIndicator> createState() => _LiveTypingIndicatorState();
}

class _LiveTypingIndicatorState extends State<_LiveTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16),
            bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = ((_ctrl.value - i * 0.2) % 1.0);
                final y = (t < 0.5 ? t * 2 : 2 - t * 2);
                return Transform.translate(
                  offset: Offset(0, -y * 4),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: 0.4 + y * 0.6),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
