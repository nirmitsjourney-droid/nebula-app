import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/chat_manager.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../services/wake_word_service.dart';
import '../services/window_manager_service.dart';
import '../widgets/sidebar.dart';
import 'chat_page.dart';
import 'landing_page.dart';
import 'live_mode_page.dart';
import 'onboarding_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late ChatManager _chatManager;
  late VoiceService _voiceService;
  late OpenAIService _openAIService;
  final WakeWordService _wakeWordService = WakeWordService();
  AppSettings? _settings;
  bool _loading = true;
  bool _showOnboarding = false;
  bool _liveModeActive = false;

  bool _sidebarExpanded = true;
  bool _sidebarOpen = false;

  late final AnimationController _drawerAnim;
  late final Animation<double> _drawerSlide;

  static const double _wideBreakpoint = 720;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drawerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _drawerSlide = CurvedAnimation(parent: _drawerAnim, curve: Curves.easeInOutCubic);
    _initialize();
  }

  Future<void> _initialize() async {
    final settings = await StorageService.instance.loadSettings();
    final openAIService = OpenAIService(settings);
    final showOnboarding = !settings.onboardingCompleted;

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _openAIService = openAIService;
      _chatManager = ChatManager(openAIService: openAIService, settings: settings);
      _voiceService = VoiceService();
      _showOnboarding = showOnboarding;
      _loading = false;
      _sidebarExpanded = true;
    });

    _wakeWordService.onWakeWordDetected = _onWakeWordDetected;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drawerAnim.dispose();
    _voiceService.dispose();
    _wakeWordService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSuggestions();
    }
  }

  void _refreshSuggestions() {
    if (!mounted) return;
    if (!_chatManager.hasActiveSession) {
      setState(() {});
    }
  }

  void _onWakeWordDetected() {
    WindowManagerService.snapToRightThird();
    WindowManagerService.focusWindow();
    if (_settings != null && !_settings!.onboardingCompleted) return;
    if (!mounted) return;
    setState(() {});
  }

  bool _isVoiceActive() {
    return _voiceService.state == VoiceState.listeningUser ||
        _voiceService.state == VoiceState.speakingAI;
  }

  bool _shouldHideSidebar() {
    if (_settings == null) return false;
    final isWide = MediaQuery.of(context).size.width >= _wideBreakpoint;

    if (!isWide && !_settings!.sidebarVisibleInTouchMode) return true;
    if (_isVoiceActive() && !_settings!.sidebarVisibleInVisionMode) return true;
    if (_voiceService.state == VoiceState.listeningUser && _settings!.sidebarAutoHideVoice) {
      return true;
    }
    return false;
  }

  void _toggleSidebar() {
    setState(() => _sidebarExpanded = !_sidebarExpanded);
  }

  void _openDrawer() {
    if (_shouldHideSidebar()) return;
    setState(() => _sidebarOpen = true);
    _drawerAnim.forward();
  }

  void _closeDrawer() {
    _drawerAnim.reverse().then((_) {
      if (mounted) setState(() => _sidebarOpen = false);
    });
  }

  void _openSettings() {
    if (_settings == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings!,
          onSettingsChanged: _onSettingsChanged,
        ),
      ),
    );
  }

  void _onSettingsChanged(AppSettings settings) {
    _settings = settings;
    _chatManager.updateSettings(settings);
    StorageService.instance.saveSettings(settings);
    _wakeWordService.setEnabled(true);
    setState(() {});
  }

  void _onOnboardingComplete(AppSettings settings) {
    _onSettingsChanged(settings);
    setState(() => _showOnboarding = false);
  }

  void _enterLiveMode() {
    setState(() => _liveModeActive = true);
  }

  void _exitLiveMode() {
    setState(() => _liveModeActive = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_showOnboarding) {
      return OnboardingPage(onComplete: _onOnboardingComplete);
    }

    if (_liveModeActive) {
      return LiveModePage(
        openAIService: _openAIService,
        voiceService: _voiceService,
        onClose: _exitLiveMode,
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= _wideBreakpoint;
    final colors = Theme.of(context).colorScheme;
    final hideSidebar = _shouldHideSidebar();

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          Row(
            children: [
              if (isWide)
                Sidebar(
                  chatManager: _chatManager,
                  voiceService: _voiceService,
                  isExpanded: hideSidebar ? false : _sidebarExpanded,
                  onToggle: _toggleSidebar,
                  onSettingsTap: _openSettings,
                  onCloseMobile: () {},
                ),
              Expanded(
                child: _ContentArea(
                  chatManager: _chatManager,
                  voiceService: _voiceService,
                  isWide: isWide,
                  onMenuTap: _openDrawer,
                  showHamburger: !hideSidebar,
                  onLiveModeTap: _enterLiveMode,
                ),
              ),
            ],
          ),

          if (!isWide && _sidebarOpen && !hideSidebar) ...[
            AnimatedBuilder(
              animation: _drawerSlide,
              builder: (context, _) {
                return GestureDetector(
                  onTap: _closeDrawer,
                  child: Container(
                    color: Colors.black.withValues(alpha: _drawerSlide.value * 0.4),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _drawerSlide,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(
                    -Sidebar.expandedWidth * (1 - _drawerSlide.value),
                    0,
                  ),
                  child: SizedBox(
                    width: Sidebar.expandedWidth,
                    child: Material(
                      color: Colors.transparent,
                      child: Sidebar(
                        chatManager: _chatManager,
                        voiceService: _voiceService,
                        isExpanded: true,
                        onToggle: _closeDrawer,
                        onSettingsTap: () {
                          _closeDrawer();
                          _openSettings();
                        },
                        onCloseMobile: _closeDrawer,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _ContentArea extends StatelessWidget {
  const _ContentArea({
    required this.chatManager,
    required this.voiceService,
    required this.isWide,
    required this.onMenuTap,
    this.showHamburger = true,
    this.onLiveModeTap,
  });

  final ChatManager chatManager;
  final VoiceService voiceService;
  final bool isWide;
  final VoidCallback onMenuTap;
  final bool showHamburger;
  final VoidCallback? onLiveModeTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      color: colors.surface,
      child: Column(
        children: [
          _TopBar(
            chatManager: chatManager,
            isWide: isWide,
            onMenuTap: onMenuTap,
            showHamburger: showHamburger,
          ),
          Divider(color: colors.outlineVariant, height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: chatManager,
              builder: (context, _) {
                if (chatManager.hasActiveSession) {
                  return ChatPage(
                    key: ValueKey(chatManager.activeSessionId),
                    chatManager: chatManager,
                    voiceService: voiceService,
                  );
                }
                return LandingPage(
                  chatManager: chatManager,
                  onLiveModeTap: onLiveModeTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.chatManager,
    required this.isWide,
    required this.onMenuTap,
    this.showHamburger = true,
  });

  final ChatManager chatManager;
  final bool isWide;
  final VoidCallback onMenuTap;
  final bool showHamburger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: chatManager,
        builder: (context, _) {
          final session = chatManager.activeSession;
          return Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (!isWide && showHamburger)
                  _barButton(colors, Icons.menu_rounded, onMenuTap),
                if (!isWide && showHamburger) const SizedBox(width: 4),
                _barButton(
                  colors,
                  Icons.arrow_back_rounded,
                  chatManager.canGoBack ? chatManager.goBack : null,
                  enabled: chatManager.canGoBack,
                ),
                const SizedBox(width: 4),
                _barButton(
                  colors,
                  Icons.arrow_forward_rounded,
                  chatManager.canGoForward ? chatManager.goForward : null,
                  enabled: chatManager.canGoForward,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: session != null ? () => chatManager.goHome() : null,
                    child: Text(
                      session?.title ?? 'Nebula',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (session != null)
                  _barButton(colors, Icons.home_rounded, chatManager.goHome),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _barButton(ColorScheme colors, IconData icon, VoidCallback? onTap, {bool enabled = true}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: colors.surfaceContainerHigh,
        ),
        child: Icon(
          icon,
          size: 19,
          color: enabled ? colors.onSurface : colors.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
