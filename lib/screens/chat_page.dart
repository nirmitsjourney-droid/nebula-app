import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_session.dart';
import '../services/chat_manager.dart';
import '../services/voice_service.dart';
import '../theme/nebula_theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.chatManager,
    required this.voiceService,
  });

  final ChatManager chatManager;
  final VoiceService voiceService;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  File? _pendingImage;
  FileAttachment? _pendingFile;
  bool _silentMode = false;

  @override
  void initState() {
    super.initState();
    widget.chatManager.addListener(_onChatChanged);
    widget.chatManager.onAIResponse = _onAIResponse;

    widget.voiceService.onTranscriptUpdate = _onVoiceTranscriptUpdate;
    widget.voiceService.onTranscriptReady = _onVoiceTranscriptReady;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    widget.chatManager.removeListener(_onChatChanged);
    widget.chatManager.onAIResponse = null;
    widget.voiceService.onTranscriptUpdate = null;
    widget.voiceService.onTranscriptReady = null;
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _onAIResponse(String text) {
    if (!_silentMode) {
      widget.voiceService.speak(text);
    }
  }

  void _onVoiceTranscriptUpdate(String text) {
    if (mounted) {
      setState(() {
        _inputController.text = text;
      });
    }
  }

  void _onVoiceTranscriptReady(String text) {
    if (mounted && text.trim().isNotEmpty) {
      _inputController.text = text;
      _sendMessage();
    }
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty && _pendingImage == null && _pendingFile == null) return;

    final imagePath = _pendingImage?.path;
    final fileAttachment = _pendingFile;
    _pendingImage = null;
    _pendingFile = null;
    _inputController.clear();

    widget.chatManager.sendMessage(
      text,
      imagePath: imagePath,
      fileAttachment: fileAttachment,
    );
  }

  Future<void> _showAttachmentPicker() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32, height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _attachmentOption(colors, Icons.photo_library_rounded, 'Gallery', _pickFromGallery),
                  const SizedBox(width: 16),
                  _attachmentOption(colors, Icons.camera_alt_rounded, 'Camera', _pickFromCamera),
                  const SizedBox(width: 16),
                  _attachmentOption(colors, Icons.attach_file_rounded, 'File', _pickFile),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _attachmentOption(ColorScheme colors, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: () { Navigator.of(context).pop(); onTap(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colors.surfaceContainer,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: colors.secondary),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (picked != null) {
      setState(() => _pendingImage = File(picked.path));
    }
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 2048);
    if (picked != null) {
      setState(() => _pendingImage = File(picked.path));
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        setState(() {
          _pendingFile = FileAttachment(
            name: file.name,
            path: file.path!,
            sizeBytes: file.size,
          );
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = widget.chatManager.activeSession;
    if (session == null) return const SizedBox.shrink();

    final messages = session.messages;
    final isThinking = widget.chatManager.isAwaitingReply;

    return Container(
      color: colors.surface,
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    itemCount: messages.length + (isThinking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length && isThinking) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(message: messages[index]);
                    },
                  ),
          ),
          _PendingAttachmentBar(
            pendingImage: _pendingImage,
            pendingFile: _pendingFile,
            onClearImage: () => setState(() => _pendingImage = null),
            onClearFile: () => setState(() => _pendingFile = null),
          ),
          _InputBar(
            controller: _inputController,
            voiceService: widget.voiceService,
            onSend: _sendMessage,
            onPickAttachment: _showAttachmentPicker,
            silentMode: _silentMode,
            onToggleSilent: () => setState(() => _silentMode = !_silentMode),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 44,
            color: colors.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'Start a conversation',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Type a message, use your voice, or attach an image',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
          ),
          border: Border.all(
            color: isUser ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(message.imagePath!),
                    width: 240,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (message.fileAttachment != null && message.isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FileChip(attachment: message.fileAttachment!),
              ),
            Text(
              message.text.isNotEmpty ? message.text : (message.isUser ? 'Sent an attachment' : ''),
              style: TextStyle(
                color: isUser ? colors.onPrimaryContainer : colors.onSurface,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final delay = i * 0.25;
                final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
                final y = (t < 0.5 ? t * 2 : 2 - t * 2);
                return Transform.translate(
                  offset: Offset(0, -y * 5),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: 0.5 + y * 0.5),
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

// ═══════════════════════════════════════════════════════════════════════════

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.voiceService,
    required this.onSend,
    this.onPickAttachment,
    this.silentMode = false,
    this.onToggleSilent,
  });

  final TextEditingController controller;
  final VoiceService voiceService;
  final VoidCallback onSend;
  final VoidCallback? onPickAttachment;
  final bool silentMode;
  final VoidCallback? onToggleSilent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            ListenableBuilder(
              listenable: voiceService,
              builder: (context, _) {
                final isListening = voiceService.state == VoiceState.listeningUser;
                return GestureDetector(
                  onTap: () {
                    if (isListening) {
                      voiceService.stopListening();
                    } else {
                      voiceService.startListening();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isListening
                          ? colors.primaryContainer
                          : colors.surfaceContainerHigh,
                      border: Border.all(
                        color: isListening ? colors.primary : colors.outlineVariant,
                      ),
                    ),
                    child: Icon(
                      isListening ? Icons.mic : Icons.mic_none_rounded,
                      size: 18,
                      color: isListening ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onToggleSilent,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: silentMode ? colors.surfaceContainerHigh : colors.primaryContainer,
                  border: Border.all(
                    color: silentMode ? colors.outlineVariant : colors.primary,
                  ),
                ),
                child: Icon(
                  silentMode ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  size: 17,
                  color: silentMode ? colors.onSurfaceVariant : colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                style: TextStyle(color: colors.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Message Nebula…',
                  hintStyle: TextStyle(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerLowest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: NebulaTheme.shapeMedium,
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: NebulaTheme.shapeMedium,
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: NebulaTheme.shapeMedium,
                    borderSide: BorderSide(color: colors.primary, width: 2),
                  ),
                  isDense: true,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onPickAttachment,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerHigh,
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Icon(
                  Icons.attach_file_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary,
                ),
                child: Icon(Icons.arrow_upward_rounded, color: colors.onPrimary, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _PendingAttachmentBar extends StatelessWidget {
  const _PendingAttachmentBar({
    this.pendingImage,
    this.pendingFile,
    this.onClearImage,
    this.onClearFile,
  });

  final File? pendingImage;
  final FileAttachment? pendingFile;
  final VoidCallback? onClearImage;
  final VoidCallback? onClearFile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (pendingImage == null && pendingFile == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (pendingImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                pendingImage!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colors.surfaceContainerHigh,
              ),
              child: Icon(Icons.insert_drive_file_outlined, size: 18, color: colors.secondary),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pendingImage != null ? 'Image attached' : pendingFile!.name,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: pendingImage != null ? onClearImage : onClearFile,
            child: Icon(Icons.close_rounded, size: 18, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _FileChip extends StatelessWidget {
  const _FileChip({required this.attachment});
  final FileAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 14, color: colors.secondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.name,
              style: TextStyle(color: colors.onSurface, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            attachment.sizeLabel,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
