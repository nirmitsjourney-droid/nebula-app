import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/chat_session.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String _fileName = 'nebula_store.json';

  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, dynamic>> loadData() async {
    try {
      final file = await _getLocalFile();
      if (!await file.exists()) {
        return {'sessions': [], 'harnesses': []};
      }
      final contents = await file.readAsString();
      final decoded = json.decode(contents) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      debugPrint('[StorageService] Error loading data: $e');
      return {'sessions': [], 'harnesses': []};
    }
  }

  Future<void> saveData({
    required List<ChatSession> sessions,
    required List<AgentHarness> harnesses,
    AppSettings? settings,
  }) async {
    try {
      final file = await _getLocalFile();
      final existing = await loadData();
      final Map<String, dynamic> data = {
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'harnesses': harnesses.map((h) => h.toJson()).toList(),
      };
      if (settings != null) {
        data['settings'] = settings.toJson();
      } else if (existing.containsKey('settings')) {
        data['settings'] = existing['settings'];
      }
      await file.writeAsString(json.encode(data));
      debugPrint('[StorageService] Data saved successfully to: ${file.path}');
    } catch (e) {
      debugPrint('[StorageService] Error saving data: $e');
    }
  }

  Future<AppSettings> loadSettings() async {
    try {
      final data = await loadData();
      final raw = data['settings'] as Map<String, dynamic>?;
      if (raw != null) {
        return AppSettings.fromJson(raw);
      }
    } catch (e) {
      debugPrint('[StorageService] Error loading settings: $e');
    }
    return AppSettings();
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final data = await loadData();
      data['settings'] = settings.toJson();
      final file = await _getLocalFile();
      await file.writeAsString(json.encode(data));
      debugPrint('[StorageService] Settings saved');
    } catch (e) {
      debugPrint('[StorageService] Error saving settings: $e');
    }
  }
}
