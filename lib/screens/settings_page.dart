import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/openai_service.dart';
import '../theme/nebula_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _settings;
  bool _apiKeyVisible = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.fromJson(widget.settings.toJson());
  }

  void _save() {
    widget.onSettingsChanged(_settings);
    Navigator.of(context).pop();
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colors.surfaceContainerHigh,
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Icon(Icons.arrow_back_rounded, color: colors.onSurface, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colors.primary,
                      ),
                      child: Text(
                        'Save',
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
            Divider(color: colors.outlineVariant, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _SettingsGroup(
                    title: 'OpenAI API',
                    children: [
                      _buildTextField(
                        label: 'Endpoint URL',
                        value: _settings.endpoint,
                        hint: 'https://api.openai.com/v1',
                        onChanged: (v) => setState(() => _settings.endpoint = v),
                      ),
                      _buildDivider(colors),
                      _buildTextField(
                        label: 'API Key',
                        value: _settings.apiKey,
                        hint: 'sk-...',
                        obscure: !_apiKeyVisible,
                        suffix: GestureDetector(
                          onTap: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                          child: Icon(
                            _apiKeyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        onChanged: (v) => setState(() => _settings.apiKey = v),
                      ),
                      _buildDivider(colors),
                      _buildTextField(
                        label: 'Model',
                        value: _settings.model,
                        hint: 'gpt-4o',
                        onChanged: (v) => setState(() => _settings.model = v),
                      ),
                      _buildDivider(colors),
                      _buildTextField(
                        label: 'System Prompt',
                        value: _settings.systemPrompt,
                        hint: 'You are a helpful assistant...',
                        maxLines: 3,
                        onChanged: (v) => setState(() => _settings.systemPrompt = v),
                      ),
                      _buildDivider(colors),
                      _buildTextField(
                        label: 'Max Tokens',
                        value: _settings.maxTokens.toString(),
                        hint: '4096',
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null) setState(() => _settings.maxTokens = n);
                        },
                      ),
                      _buildDivider(colors),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.thermostat_rounded, size: 18, color: colors.secondary),
                                const SizedBox(width: 8),
                                Text(
                                  'Temperature: ${_settings.temperature.toStringAsFixed(1)}',
                                  style: TextStyle(color: colors.onSurface, fontSize: 14),
                                ),
                              ],
                            ),
                            Slider(
                              value: _settings.temperature,
                              min: 0.0,
                              max: 2.0,
                              divisions: 20,
                              activeColor: colors.secondary,
                              inactiveColor: colors.outlineVariant,
                              onChanged: (v) => setState(() => _settings.temperature = v),
                            ),
                          ],
                        ),
                      ),
                      _buildDivider(colors),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.wifi_tethering_rounded, size: 18, color: colors.secondary),
                                const SizedBox(width: 8),
                                Text(
                                  'Test Connection',
                                  style: TextStyle(color: colors.onSurface, fontSize: 14),
                                ),
                                const Spacer(),
                                if (_testing)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  GestureDetector(
                                    onTap: _testConnection,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: colors.surfaceContainerHigh,
                                        border: Border.all(color: colors.outlineVariant),
                                      ),
                                      child: Text(
                                        'Test',
                                        style: TextStyle(
                                          color: colors.onSurface,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (_testResult != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _testResult!,
                                style: TextStyle(
                                  color: _testResult == 'Connection successful!'
                                      ? colors.primary
                                      : colors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SettingsGroup(
                    title: 'Sidebar',
                    children: [
                      _buildSwitchTile(
                        icon: Icons.touch_app_rounded,
                        label: 'Visible in touch mode',
                        value: _settings.sidebarVisibleInTouchMode,
                        onChanged: (v) => setState(() => _settings.sidebarVisibleInTouchMode = v),
                      ),
                      _buildDivider(colors),
                      _buildSwitchTile(
                        icon: Icons.visibility_rounded,
                        label: 'Visible in vision mode',
                        value: _settings.sidebarVisibleInVisionMode,
                        onChanged: (v) => setState(() => _settings.sidebarVisibleInVisionMode = v),
                      ),
                      _buildDivider(colors),
                      _buildSwitchTile(
                        icon: Icons.mic_none_rounded,
                        label: 'Auto-hide during voice input',
                        value: _settings.sidebarAutoHideVoice,
                        onChanged: (v) => setState(() => _settings.sidebarAutoHideVoice = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SettingsGroup(
                    title: 'Appearance',
                    children: [
                      _buildSwitchTile(
                        icon: Icons.palette_outlined,
                        label: 'Use system colors',
                        description: 'Follow system light/dark mode',
                        value: _settings.useSystemColors,
                        onChanged: (v) => setState(() => _settings.useSystemColors = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SettingsGroup(
                    title: 'About',
                    children: [
                      _buildInfoTile(Icons.info_outline_rounded, 'Version', '1.0.0'),
                      _buildDivider(colors),
                      _buildInfoTile(
                        Icons.description_outlined,
                        'Description',
                        'General-purpose AI assistant',
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    String? hint,
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    Widget? suffix,
    required ValueChanged<String> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController.fromValue(
              TextEditingValue(
                text: value,
                selection: TextSelection.collapsed(offset: value.length),
              ),
            ),
            obscureText: obscure,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: TextStyle(color: colors.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 14,
              ),
              suffixIcon: suffix,
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
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String label,
    String? description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: colors.onSurface, fontSize: 14),
                ),
                if (description != null)
                  Text(
                    description,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: colors.primary,
            inactiveTrackColor: colors.surfaceContainerHigh,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colors.secondary, size: 22),
      title: Text(label, style: TextStyle(color: colors.onSurface, fontSize: 15)),
      trailing: Text(
        value,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colors) {
    return Divider(height: 1, indent: 56, color: colors.outlineVariant);
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            letterSpacing: 1.2,
            color: colors.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: NebulaTheme.shapeLarge,
            color: colors.surfaceContainer,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
