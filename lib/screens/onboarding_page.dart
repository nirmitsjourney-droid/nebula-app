import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/openai_service.dart';
import '../theme/nebula_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onComplete,
  });

  final ValueChanged<AppSettings> onComplete;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  late AppSettings _settings;
  bool _apiKeyVisible = false;
  bool _testing = false;
  String? _testResult;


  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _settings = AppSettings();
  }

  void _finish() {
    _settings.onboardingCompleted = true;
    widget.onComplete(_settings);
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final service = OpenAIService(_settings);
    final error = await service.testConnection();

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = error ?? 'Connection successful!';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Steps indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: List.generate(4, (i) {
                  final isActive = i == _step;
                  final isDone = i < _step;
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: isDone || isActive ? colors.primary : colors.outlineVariant,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),

            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _buildWelcome(colors),
                  _buildApiConfig(colors),
                  _buildTestConnection(colors),
                  _buildComplete(colors),
                ],
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_step > 0)
                    GestureDetector(
                      onTap: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: NebulaTheme.shapeSmall,
                          color: colors.surfaceContainerHigh,
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Text(
                          'Back',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _step < 3 ? _nextStep : _finish,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: NebulaTheme.shapeSmall,
                        color: colors.primary,
                      ),
                      child: Text(
                        _step == 3 ? 'Get Started' : 'Continue',
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _nextStep() {
    if (_step == 1) {
      // Validate API config - API key is required
      if (_settings.apiKey.trim().isEmpty && !_settings.endpoint.contains('localhost')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an API key')),
        );
        return;
      }
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Step 0: Welcome ──────────────────────────────────────────────────

  Widget _buildWelcome(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
            ),
            child: Icon(Icons.auto_awesome, size: 36, color: colors.onPrimary),
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome to Nebula',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nebula is your lightweight AI assistant — a replacement for Siri, Copilot, and Google Assistant. Connect any OpenAI-compatible API and start getting things done.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _featureChip(colors, Icons.code_rounded, 'Code'),
              const SizedBox(width: 12),
              _featureChip(colors, Icons.auto_awesome, 'AI Chat'),
              const SizedBox(width: 12),
              _featureChip(colors, Icons.mic, 'Voice'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureChip(ColorScheme colors, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colors.surfaceContainerHigh,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.secondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: colors.onSurface, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Step 1: API Configuration ────────────────────────────────────────

  Widget _buildApiConfig(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configure API',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to any OpenAI-compatible endpoint.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Text(
            'ENDPOINT URL',
            style: TextStyle(
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: _settings.endpoint),
            style: TextStyle(color: colors.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://api.openai.com/v1',
              hintStyle: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 14,
              ),
              filled: true,
              fillColor: colors.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              isDense: true,
            ),
            onChanged: (v) => _settings.endpoint = v,
          ),
          const SizedBox(height: 16),
          Text(
            'API KEY',
            style: TextStyle(
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: _settings.apiKey),
            obscureText: !_apiKeyVisible,
            style: TextStyle(color: colors.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'sk-...',
              hintStyle: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 14,
              ),
              suffixIcon: GestureDetector(
                onTap: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                child: Icon(
                  _apiKeyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
              filled: true,
              fillColor: colors.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              isDense: true,
            ),
            onChanged: (v) => _settings.apiKey = v,
          ),
          const SizedBox(height: 16),
          Text(
            'MODEL',
            style: TextStyle(
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: _settings.model),
            style: TextStyle(color: colors.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'gpt-4o',
              hintStyle: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 14,
              ),
              filled: true,
              fillColor: colors.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: NebulaTheme.shapeSmall,
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              isDense: true,
            ),
            onChanged: (v) => _settings.model = v,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Supports OpenAI, Azure OpenAI, Ollama, vLLM, Groq, and any OpenAI-compatible API.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 2: Test Connection ──────────────────────────────────────────

  Widget _buildTestConnection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceContainerHigh,
            ),
            child: Icon(
              _testResult == 'Connection successful!'
                  ? Icons.check_circle_rounded
                  : _testResult != null
                      ? Icons.error_outline_rounded
                      : Icons.wifi_tethering_rounded,
              size: 32,
              color: _testResult == 'Connection successful!'
                  ? colors.primary
                  : _testResult != null
                      ? colors.error
                      : colors.secondary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Test Connection',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Verify your API endpoint is reachable and working.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 32),
          if (_testing)
            const Column(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 12),
                Text('Testing connection...'),
              ],
            )
          else ...[
            if (_testResult != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: NebulaTheme.shapeSmall,
                  color: _testResult == 'Connection successful!'
                      ? colors.primaryContainer.withValues(alpha: 0.3)
                      : colors.errorContainer.withValues(alpha: 0.3),
                  border: Border.all(
                    color: _testResult == 'Connection successful!'
                        ? colors.primary
                        : colors.error,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult == 'Connection successful!'
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 20,
                      color: _testResult == 'Connection successful!'
                          ? colors.primary
                          : colors.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            GestureDetector(
              onTap: _testConnection,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: NebulaTheme.shapeSmall,
                  color: colors.primary,
                ),
                child: Text(
                  'Run Test',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                _nextStep();
              },
              child: Text(
                'Skip test',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 3: Complete ─────────────────────────────────────────────────

  Widget _buildComplete(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
            ),
            child: Icon(Icons.auto_awesome, size: 36, color: colors.onPrimary),
          ),
          const SizedBox(height: 24),
          Text(
            'All Set!',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nebula is ready to help. Start a new chat or use voice commands to interact with your AI assistant.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: NebulaTheme.shapeSmall,
              color: colors.surfaceContainer,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                _configRow(colors, 'Endpoint', _settings.endpoint),
                const SizedBox(height: 8),
                _configRow(colors, 'Model', _settings.model),
                const SizedBox(height: 8),
                _configRow(
                  colors,
                  'API Key',
                  _settings.apiKey.isNotEmpty
                      ? '${_settings.apiKey.substring(0, 8)}...${_settings.apiKey.substring(_settings.apiKey.length - 4)}'
                      : 'Not set',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _configRow(ColorScheme colors, String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: colors.onSurface, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
