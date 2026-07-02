import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../services/chat_manager.dart';
import '../theme/nebula_theme.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key, required this.chatManager, this.onLiveModeTap});

  final ChatManager chatManager;
  final VoidCallback? onLiveModeTap;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  List<AISuggestion> _suggestions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final suggestions = await widget.chatManager.fetchSuggestions();
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      color: colors.surface,
      child: CustomScrollView(
        slivers: [
          // ── Dashboard header ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
              child: Column(
                children: [
                  const Center(child: _MiniOrb()),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'Hi, I\'m Nebula',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Your AI assistant — ask me anything',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Quick action chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _quickChip(colors, Icons.chat_bubble_outline_rounded, 'Start Chat', () {
                        widget.chatManager.createSession(type: ChatSessionType.chat);
                      }),
                      _quickChip(colors, Icons.mic_none_rounded, 'Voice Input', () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tap the mic in chat to use voice')),
                        );
                      }),
                      if (widget.onLiveModeTap != null)
                        _quickChip(colors, Icons.videocam_rounded, 'Live Mode', widget.onLiveModeTap!),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Suggestions section (scrollable, below fold) ──────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
              child: Row(
                children: [
                  Text(
                    'SUGGESTIONS',
                    style: TextStyle(
                      letterSpacing: 1.5,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (!_loading)
                      GestureDetector(
                        onTap: () {
                          widget.chatManager.invalidateSuggestions();
                          setState(() => _loading = true);
                          _loadSuggestions();
                        },
                      child: Icon(Icons.refresh_rounded, size: 18, color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),

          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SuggestionTile(
                        suggestion: _suggestions[index],
                        onTap: () {
                          widget.chatManager.createSession(
                            initialPrompt: _suggestions[index].prompt,
                            type: ChatSessionType.chat,
                          );
                        },
                      ),
                    );
                  },
                  childCount: _suggestions.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _quickChip(ColorScheme colors, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colors.secondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _MiniOrb extends StatefulWidget {
  const _MiniOrb();

  @override
  State<_MiniOrb> createState() => _MiniOrbState();
}

class _MiniOrbState extends State<_MiniOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = 1.0 + (_ctrl.value * 0.12);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
            ),
            child: Icon(Icons.auto_awesome, color: colors.onPrimary, size: 30),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _SuggestionTile extends StatefulWidget {
  const _SuggestionTile({required this.suggestion, required this.onTap});
  final AISuggestion suggestion;
  final VoidCallback onTap;

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: NebulaTheme.shapeMedium,
            color: colors.surfaceContainer,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.suggestion.backgroundColor,
                ),
                child: Icon(widget.suggestion.icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.suggestion.prompt,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.suggestion.description,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
