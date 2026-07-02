import 'package:flutter/material.dart';

import 'models/app_settings.dart';
import 'screens/app_shell.dart';
import 'services/storage_service.dart';
import 'theme/nebula_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NebulaApp());
}

class NebulaApp extends StatefulWidget {
  const NebulaApp({super.key});

  @override
  State<NebulaApp> createState() => _NebulaAppState();
}

class _NebulaAppState extends State<NebulaApp> with WidgetsBindingObserver {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await StorageService.instance.loadSettings();
    if (mounted) setState(() => _settings = settings);
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final useSystem = _settings?.useSystemColors ?? true;
    final themeMode = useSystem
        ? ThemeMode.system
        : ThemeMode.dark;

    return MaterialApp(
      title: 'Nebula',
      debugShowCheckedModeBanner: false,
      theme: NebulaTheme.lightTheme,
      darkTheme: NebulaTheme.darkTheme,
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
