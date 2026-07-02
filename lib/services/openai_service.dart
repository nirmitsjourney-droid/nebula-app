import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/chat_session.dart';

class OpenAIService {
  OpenAIService(this.settings);

  AppSettings settings;

  void updateSettings(AppSettings s) {
    settings = s;
  }

  String get _endpoint => settings.endpoint.replaceAll(RegExp(r'/+$'), '');
  String get _apiKey => settings.apiKey;
  String get _model => settings.model;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
      };

  Future<String> sendChatCompletion(List<ChatMessage> messages, {String? sessionId}) async {
    final url = Uri.parse('$_endpoint/chat/completions');
    final memoryContent = _loadMemoryMd();
    final chatMemory = sessionId != null ? await _loadChatMemory(sessionId) : null;

    final systemParts = <String>[];
    if (settings.systemPrompt.isNotEmpty) systemParts.add(settings.systemPrompt);
    if (memoryContent != null) systemParts.add(memoryContent);
    if (chatMemory != null) systemParts.add('## Previous Session Summary\n$chatMemory');

    final apiMessages = <Map<String, dynamic>>[];

    apiMessages.add({
      'role': 'system',
      'content': systemParts.join('\n\n'),
    });

    for (final msg in messages) {
      if (msg.imagePath != null && msg.isUser) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': msg.text},
            {'type': 'image_url', 'image_url': {'url': _imageToBase64(msg.imagePath!)}},
          ],
        });
      } else {
        apiMessages.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text,
        });
      }
    }

    final body = {
      'model': _model,
      'messages': apiMessages,
      'max_tokens': settings.maxTokens,
      'temperature': settings.temperature,
    };

    try {
      final response = await http
          .post(url, headers: _headers, body: json.encode(body))
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          if (message != null) {
            return (message['content'] as String?)?.trim() ?? '';
          }
        }
        return '';
      } else {
        final errorBody = response.body;
        debugPrint('[OpenAI] Error ${response.statusCode}: $errorBody');
        return 'Error: ${response.statusCode} - ${_extractError(errorBody)}';
      }
    } catch (e) {
      debugPrint('[OpenAI] Request failed: $e');
      return 'Connection error: $e';
    }
  }

  Future<void> saveChatMemory(String sessionId, String summary) async {
    try {
      final dir = await _getChatsDir();
      final file = File('${dir.path}/$sessionId.md');
      await file.writeAsString(summary);
    } catch (e) {
      debugPrint('[OpenAI] Failed to save chat memory: $e');
    }
  }

  Future<String?> _loadChatMemory(String sessionId) async {
    try {
      final dir = await _getChatsDir();
      final file = File('${dir.path}/$sessionId.md');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('[OpenAI] Failed to load chat memory: $e');
    }
    return null;
  }

  Future<Directory> _getChatsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final chatsDir = Directory('${appDir.path}/chats');
    if (!await chatsDir.exists()) {
      await chatsDir.create(recursive: true);
    }
    return chatsDir;
  }

  Future<Map<String, String>> listChatMemories() async {
    final memories = <String, String>{};
    try {
      final dir = await _getChatsDir();
      final files = dir.listSync().whereType<File>();
      for (final file in files) {
        if (file.path.endsWith('.md')) {
          final id = file.uri.pathSegments.last.replaceAll('.md', '');
          memories[id] = await file.readAsString();
        }
      }
    } catch (e) {
      debugPrint('[OpenAI] Failed to list chat memories: $e');
    }
    return memories;
  }

  // ── Suggestions ────────────────────────────────────────────────────────

  Future<List<AISuggestion>> generateSuggestions() async {
    final url = Uri.parse('$_endpoint/chat/completions');

    final body = {
      'model': _model,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a helpful AI assistant. Generate 4 brief, diverse suggestions for things a user might want to ask or do. '
                  'Return ONLY a JSON array of objects with "prompt", "description", and "icon" fields. '
                  'The icon field must be a valid Material Icons name (e.g., "search", "settings", "lightbulb", "rocket_launch", "chat", "edit", "terminal", "music_note", "wb_sunny", "restaurant", "flight", "school", "favorite", "star"). '
                  'Keep prompts under 60 chars and descriptions under 40 chars. Make them practical everyday tasks.',
        },
        {
          'role': 'user',
          'content': 'Generate 4 diverse suggestions for a general-purpose AI assistant.',
        },
      ],
      'max_tokens': 500,
      'temperature': 0.8,
    };

    try {
      final response = await http
          .post(url, headers: _headers, body: json.encode(body))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          if (message != null) {
            return _parseSuggestions(message['content'] as String? ?? '');
          }
        }
      }
    } catch (e) {
      debugPrint('[OpenAI] Suggestion generation failed: $e');
    }
    return _fallbackSuggestions();
  }

  List<AISuggestion> _parseSuggestions(String content) {
    try {
      final cleaned = content
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```$', multiLine: true), '')
          .trim();
      final list = json.decode(cleaned) as List<dynamic>;
      final icons = {
        'search': Icons.search_rounded,
        'settings': Icons.settings_rounded,
        'lightbulb': Icons.lightbulb_rounded,
        'rocket_launch': Icons.rocket_launch_rounded,
        'chat': Icons.chat_bubble_outline_rounded,
        'edit': Icons.edit_rounded,
        'terminal': Icons.terminal_rounded,
        'music_note': Icons.music_note_rounded,
        'wb_sunny': Icons.wb_sunny_rounded,
        'restaurant': Icons.restaurant_rounded,
        'flight': Icons.flight_rounded,
        'school': Icons.school_rounded,
        'favorite': Icons.favorite_rounded,
        'star': Icons.star_rounded,
        'code': Icons.code_rounded,
        'brush': Icons.brush_rounded,
        'bug_report': Icons.bug_report_rounded,
        'description': Icons.description_rounded,
        'auto_awesome': Icons.auto_awesome,
        'build': Icons.build_rounded,
      };
      final colors = [
        const Color(0xFF6750A4),
        const Color(0xFF006A6A),
        const Color(0xFF7D5260),
        const Color(0xFF49454F),
      ];
      return list.take(4).toList().asMap().entries.map((entry) {
        final item = entry.value as Map<String, dynamic>;
        final iconName = (item['icon'] as String? ?? 'auto_awesome').toLowerCase();
        return AISuggestion(
          prompt: item['prompt'] as String? ?? 'Ask me something',
          description: item['description'] as String? ?? 'Get started',
          icon: icons[iconName] ?? Icons.auto_awesome,
          backgroundColor: colors[entry.key % colors.length],
        );
      }).toList();
    } catch (e) {
      debugPrint('[OpenAI] Parse suggestions failed: $e');
      return _fallbackSuggestions();
    }
  }

  List<AISuggestion> _fallbackSuggestions() {
    return const [
      AISuggestion(
        prompt: 'What\'s the weather like today?',
        description: 'Get current weather',
        icon: Icons.wb_sunny_rounded,
        backgroundColor: Color(0xFF6750A4),
      ),
      AISuggestion(
        prompt: 'Help me write an email',
        description: 'Draft professional emails',
        icon: Icons.edit_rounded,
        backgroundColor: Color(0xFF006A6A),
      ),
      AISuggestion(
        prompt: 'Explain quantum computing',
        description: 'Simplify complex topics',
        icon: Icons.lightbulb_rounded,
        backgroundColor: Color(0xFF7D5260),
      ),
      AISuggestion(
        prompt: 'Plan a weekend itinerary',
        description: 'Trip & activity planning',
        icon: Icons.flight_rounded,
        backgroundColor: Color(0xFF49454F),
      ),
    ];
  }

  // ── File Content Reading ────────────────────────────────────────────────

  String readFileContent(FileAttachment file) {
    if (!file.isTextBased) return '';
    try {
      final f = File(file.path);
      if (!f.existsSync()) return '';
      final content = f.readAsStringSync();
      final ext = file.name.split('.').last;
      return '--- File: ${file.name} ---\n```$ext\n$content\n```\n';
    } catch (e) {
      debugPrint('[OpenAI] Failed to read file: $e');
      return '';
    }
  }

  // ── SSE Streaming ───────────────────────────────────────────────────────

  Stream<String> streamChatCompletion(List<ChatMessage> messages, {String? sessionId}) async* {
    final url = Uri.parse('$_endpoint/chat/completions');
    final memoryContent = _loadMemoryMd();
    final chatMemory = sessionId != null ? await _loadChatMemory(sessionId) : null;

    final systemParts = <String>[];
    if (settings.systemPrompt.isNotEmpty) systemParts.add(settings.systemPrompt);
    if (memoryContent != null) systemParts.add(memoryContent);
    if (chatMemory != null) systemParts.add('## Previous Session Summary\n$chatMemory');

    final apiMessages = <Map<String, dynamic>>[];
    apiMessages.add({
      'role': 'system',
      'content': systemParts.join('\n\n'),
    });

    for (final msg in messages) {
      if (msg.imagePath != null && msg.isUser) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': msg.text},
            {'type': 'image_url', 'image_url': {'url': _imageToBase64(msg.imagePath!)}},
          ],
        });
      } else {
        apiMessages.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text,
        });
      }
    }

    final body = {
      'model': _model,
      'messages': apiMessages,
      'max_tokens': settings.maxTokens,
      'temperature': settings.temperature,
      'stream': true,
    };

    try {
      final request = http.Request('POST', url)
        ..headers.addAll(_headers)
        ..body = json.encode(body);

      final streamedResponse = await http.Client().send(request).timeout(const Duration(seconds: 120));
      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final chunk = json.decode(data) as Map<String, dynamic>;
            final choices = chunk['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[OpenAI] Stream error: $e');
      yield 'Error: $e';
    }
  }

  // ── Image & Memory Helpers ─────────────────────────────────────────────

  String _imageToBase64(String path) {
    try {
      final file = File(path);
      final bytes = file.readAsBytesSync();
      final ext = path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'png' : ext == 'webp' ? 'webp' : 'jpeg';
      return 'data:image/$mime;base64,${base64.encode(bytes)}';
    } catch (e) {
      debugPrint('[OpenAI] Failed to encode image: $e');
      return '';
    }
  }

  String? _loadMemoryMd() {
    try {
      final file = File('memory.md');
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    } catch (e) {
      debugPrint('[OpenAI] Failed to load memory.md: $e');
    }
    return null;
  }

  // ── Connection Test ────────────────────────────────────────────────────

  Future<String?> testConnection() async {
    if (_apiKey.isEmpty) {
      return 'API key is required.';
    }

    final url = Uri.parse('$_endpoint/models');

    try {
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return null;
      } else {
        return 'Error ${response.statusCode}: ${_extractError(response.body)}';
      }
    } catch (e) {
      return 'Connection failed: $e';
    }
  }

  String _extractError(String body) {
    try {
      final data = json.decode(body) as Map<String, dynamic>;
      final error = data['error'] as Map<String, dynamic>?;
      if (error != null) {
        return error['message'] as String? ?? body;
      }
    } catch (_) {}
    return body.length > 100 ? '${body.substring(0, 100)}...' : body;
  }
}
