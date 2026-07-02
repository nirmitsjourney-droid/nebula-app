import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../services/chat_manager.dart';
import '../services/voice_service.dart';
import '../theme/nebula_theme.dart';
import 'audio_visualizer.dart';
import 'create_agent_dialog.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.chatManager,
    required this.voiceService,
    required this.isExpanded,
    required this.onToggle,
    required this.onSettingsTap,
    required this.onCloseMobile,
  });

  final ChatManager chatManager;
  final VoiceService voiceService;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onSettingsTap;
  final VoidCallback onCloseMobile;

  static const double expandedWidth = 272.0;
  static const double collapsedWidth = 68.0;

  double get width => isExpanded ? expandedWidth : collapsedWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: NebulaTheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _SidebarHeader(isExpanded: isExpanded, onToggle: onToggle),
          const SizedBox(height: 8),
          _divider(colors),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.add_rounded,
            label: 'New Chat',
            isExpanded: isExpanded,
            onTap: () {
              chatManager.createSession(type: ChatSessionType.chat);
              onCloseMobile();
            },
          ),
          _ActionButton(
            icon: Icons.smart_toy_outlined,
            label: 'New Agent',
            isExpanded: isExpanded,
            onTap: () {
              onCloseMobile();
              CreateAgentDialog.show(context, chatManager);
            },
          ),
          const SizedBox(height: 8),
          _divider(colors),
          Expanded(
            child: ListenableBuilder(
              listenable: chatManager,
              builder: (context, _) {
                final sessions = chatManager.sessions;
                if (sessions.isEmpty) {
                  return Center(
                    child: isExpanded
                        ? Text(
                            'No chats yet',
                            style: TextStyle(
                              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          )
                        : const SizedBox.shrink(),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final isActive = session.id == chatManager.activeSessionId;
                    return _ChatHistoryTile(
                      session: session,
                      isActive: isActive,
                      isExpanded: isExpanded,
                      onTap: () {
                        chatManager.selectSession(session.id);
                        onCloseMobile();
                      },
                      onDelete: () => chatManager.deleteSession(session.id),
                    );
                  },
                );
              },
            ),
          ),
          _divider(colors),
          _BottomSection(
            voiceService: voiceService,
            isExpanded: isExpanded,
            onSettingsTap: onSettingsTap,
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme colors) {
    return Divider(
      height: 1,
      thickness: 1,
      color: colors.outlineVariant,
      indent: isExpanded ? 16 : 12,
      endIndent: isExpanded ? 16 : 12,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.isExpanded, required this.onToggle});
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 16 : 10, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
            ),
            child: Icon(Icons.auto_awesome, size: 20, color: colors.onPrimary),
          ),
          if (isExpanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'NEBULA',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ],
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: isExpanded ? 32 : 40,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colors.surfaceContainerHigh,
              ),
              child: Icon(
                isExpanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isExpanded,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.isExpanded ? 12 : 10, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 42,
            decoration: BoxDecoration(
              borderRadius: NebulaTheme.shapeSmall,
              color: _hovered ? colors.surfaceContainerHigh : Colors.transparent,
            ),
            padding: EdgeInsets.symmetric(horizontal: widget.isExpanded ? 12 : 0),
            child: Row(
              mainAxisAlignment:
                  widget.isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 20, color: colors.secondary),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 12),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _ChatHistoryTile extends StatefulWidget {
  const _ChatHistoryTile({
    required this.session,
    required this.isActive,
    required this.isExpanded,
    required this.onTap,
    required this.onDelete,
  });
  final ChatSession session;
  final bool isActive;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ChatHistoryTile> createState() => _ChatHistoryTileState();
}

class _ChatHistoryTileState extends State<_ChatHistoryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.isExpanded ? 12 : 10, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 42,
            decoration: BoxDecoration(
              borderRadius: NebulaTheme.shapeSmall,
              color: widget.isActive
                  ? colors.primaryContainer
                  : _hovered
                      ? colors.surfaceContainerHigh
                      : Colors.transparent,
              border: widget.isActive ? Border.all(color: colors.primary) : null,
            ),
            padding: EdgeInsets.symmetric(horizontal: widget.isExpanded ? 12 : 0),
            child: Row(
              mainAxisAlignment:
                  widget.isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  widget.session.icon,
                  size: 18,
                  color: widget.isActive ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                ),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isActive ? colors.onPrimaryContainer : colors.onSurface,
                        fontSize: 13,
                        fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (_hovered || widget.isActive)
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: widget.isActive
                            ? colors.onPrimaryContainer.withValues(alpha: 0.6)
                            : colors.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _BottomSection extends StatelessWidget {
  const _BottomSection({
    required this.voiceService,
    required this.isExpanded,
    required this.onSettingsTap,
  });
  final VoiceService voiceService;
  final bool isExpanded;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 16 : 8, vertical: 10),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: AudioVisualizer(
              voiceService: voiceService,
              height: 44,
              barWidth: isExpanded ? 3.5 : 2.5,
              barSpacing: isExpanded ? 2.5 : 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              ListenableBuilder(
                listenable: voiceService,
                builder: (context, _) {
                  final isListening = voiceService.state == VoiceState.listeningUser;
                  final isSpeaking = voiceService.state == VoiceState.speakingAI;
                  if (isExpanded) {
                    return Expanded(
                      child: Text(
                        isListening
                            ? 'Listening…'
                            : isSpeaking
                                ? 'Speaking…'
                                : 'Voice idle',
                        style: TextStyle(
                          color: isListening
                              ? colors.primary
                              : isSpeaking
                                  ? colors.secondary
                                  : colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              GestureDetector(
                onTap: onSettingsTap,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: NebulaTheme.shapeSmall,
                    color: colors.surfaceContainerHigh,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
