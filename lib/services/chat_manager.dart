import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/chat_session.dart';
import 'openai_service.dart';
import 'storage_service.dart';

class ChatManager extends ChangeNotifier {
  ChatManager({
    OpenAIService? openAIService,
    AppSettings? settings,
  })  : _openAIService = openAIService ?? OpenAIService(AppSettings()),
        _settings = settings ?? AppSettings() {
    _loadFromStorage();
  }

  final OpenAIService _openAIService;
  AppSettings _settings;

  AppSettings get settings => _settings;

  void updateSettings(AppSettings s) {
    _settings = s;
    _openAIService.updateSettings(s);
  }

  final List<ChatSession> _sessions = [];
  final List<AgentHarness> _harnesses = [];
  String? _activeSessionId;
  int _idCounter = 0;
  int _harnessCounter = 0;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  List<AgentHarness> get harnesses => List.unmodifiable(_harnesses);

  ChatSession? get activeSession {
    if (_activeSessionId == null) return null;
    final index = _sessions.indexWhere((s) => s.id == _activeSessionId);
    return index == -1 ? null : _sessions[index];
  }

  String? get activeSessionId => _activeSessionId;
  bool get hasActiveSession => _activeSessionId != null;

  final List<String> _history = [];
  int _historyIndex = -1;

  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _history.length - 1;

  void goBack() {
    if (!canGoBack) return;
    _historyIndex--;
    _activeSessionId = _history[_historyIndex];
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) return;
    _historyIndex++;
    _activeSessionId = _history[_historyIndex];
    notifyListeners();
  }

  void _pushHistory(String id) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(id);
    _historyIndex = _history.length - 1;
  }

  Future<void> _loadFromStorage() async {
    final data = await StorageService.instance.loadData();

    final rawHarnesses = data['harnesses'] as List<dynamic>? ?? [];
    _harnesses.clear();
    for (final raw in rawHarnesses) {
      try {
        _harnesses.add(AgentHarness.fromJson(raw as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[ChatManager] Error parsing harness JSON: $e');
      }
    }
    _harnessCounter = _harnesses.length;

    final rawSessions = data['sessions'] as List<dynamic>? ?? [];
    _sessions.clear();
    for (final raw in rawSessions) {
      try {
        _sessions.add(ChatSession.fromJson(raw as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[ChatManager] Error parsing session JSON: $e');
      }
    }
    _idCounter = _sessions.length + 10;

    notifyListeners();
  }

  Future<void> _triggerSave() async {
    await StorageService.instance.saveData(
      sessions: _sessions,
      harnesses: _harnesses,
      settings: _settings,
    );
  }

  AgentHarness createHarness({
    required String name,
    required AgentHarnessType type,
    String agentMd = '',
    String connectionUrl = '',
  }) {
    _harnessCounter++;
    final harness = AgentHarness(
      id: 'harness_$_harnessCounter',
      name: name,
      type: type,
      agentMd: agentMd,
      connectionUrl: connectionUrl,
    );
    _harnesses.add(harness);
    _triggerSave();
    notifyListeners();
    return harness;
  }

  void deleteHarness(String harnessId) {
    _harnesses.removeWhere((h) => h.id == harnessId);
    _triggerSave();
    notifyListeners();
  }

  ChatSession createSession({
    String? initialPrompt,
    ChatSessionType type = ChatSessionType.chat,
    String? agentHarnessId,
  }) {
    _idCounter++;

    String title = initialPrompt ?? _defaultTitle(type);
    if (agentHarnessId != null) {
      final harness = _harnesses.firstWhere((h) => h.id == agentHarnessId);
      title = '${harness.name} Chat';
    }

    final session = ChatSession(
      id: 'session_$_idCounter',
      title: title,
      type: type,
      agentHarnessId: agentHarnessId,
    );
    _sessions.insert(0, session);
    _activeSessionId = session.id;
    _pushHistory(session.id);
    notifyListeners();

    if (initialPrompt != null && initialPrompt.isNotEmpty) {
      sendMessage(initialPrompt);
    } else {
      _triggerSave();
    }

    return session;
  }

  void selectSession(String id) {
    if (_activeSessionId == id) return;
    _activeSessionId = id;
    _pushHistory(id);
    notifyListeners();
  }

  void goHome() {
    _activeSessionId = null;
    notifyListeners();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    if (_activeSessionId == id) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }
    _triggerSave();
    notifyListeners();
  }

  // ── AI Suggestions ─────────────────────────────────────────────────────

  List<AISuggestion>? _cachedSuggestions;

  Future<List<AISuggestion>> fetchSuggestions() async {
    if (_cachedSuggestions != null) return _cachedSuggestions!;

    List<AISuggestion> result;
    if (_settings.apiKey.trim().isNotEmpty) {
      try {
        result = await _openAIService.generateSuggestions();
      } catch (e) {
        debugPrint('[ChatManager] Suggestion generation failed: $e');
        result = _fallbackSuggestions();
      }
    } else {
      result = _fallbackSuggestions();
    }
    _cachedSuggestions = result;
    return result;
  }

  void invalidateSuggestions() {
    _cachedSuggestions = null;
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

  // ── Messaging ─────────────────────────────────────────────────────────

  bool _isAwaitingReply = false;
  bool get isAwaitingReply => _isAwaitingReply;

  ValueChanged<String>? onAIResponse;

  void sendMessage(String text, {String? imagePath, FileAttachment? fileAttachment}) {
    final session = activeSession;
    if (session == null || _isAwaitingReply) return;

    String messageText = text;
    if (fileAttachment != null && fileAttachment.isTextBased) {
      final content = _openAIService.readFileContent(fileAttachment);
      if (content.isNotEmpty) {
        messageText = '$text\n\n$content';
      }
    }

    final msgId = '${session.id}_msg_${session.messages.length}';
    session.messages.add(ChatMessage(
      id: msgId,
      text: messageText,
      isUser: true,
      imagePath: imagePath,
      fileAttachment: fileAttachment,
    ));

    if (session.messages.where((m) => m.isUser).length == 1) {
      String title;
      if (text.isNotEmpty) {
        title = text.length > 30 ? '${text.substring(0, 30)}…' : text;
      } else if (imagePath != null) {
        title = 'Image chat';
      } else if (fileAttachment != null) {
        title = 'File: ${fileAttachment.name}';
      } else {
        title = 'New Chat';
      }
      session.title = title;
    }

    notifyListeners();
    _fetchReply(session);
  }

  Stream<String> streamReply(String text, {String? imagePath, FileAttachment? fileAttachment}) async* {
    String messageText = text;
    if (fileAttachment != null && fileAttachment.isTextBased) {
      final content = _openAIService.readFileContent(fileAttachment);
      if (content.isNotEmpty) {
        messageText = '$text\n\n$content';
      }
    }

    final session = activeSession;
    final messages = session != null ? session.messages : <ChatMessage>[];

    final tempMessages = List<ChatMessage>.from(messages);
    tempMessages.add(ChatMessage(
      id: 'temp',
      text: messageText,
      isUser: true,
      imagePath: imagePath,
      fileAttachment: fileAttachment,
    ));

    await for (final chunk in _openAIService.streamChatCompletion(tempMessages)) {
      yield chunk;
    }
  }

  void _fetchReply(ChatSession session) {
    _isAwaitingReply = true;
    notifyListeners();

    if (_settings.apiKey.trim().isEmpty) {
      _deliverStubReply(session);
      return;
    }

    _openAIService.sendChatCompletion(session.messages, sessionId: session.id).then((reply) {
      if (!_isAwaitingReply) return;
      _deliverReply(session, reply);
    }).catchError((e) {
      debugPrint('[ChatManager] API error, falling back to stub: $e');
      _deliverStubReply(session);
    });
  }

  void _deliverReply(ChatSession session, String reply) {
    final replyId = '${session.id}_msg_${session.messages.length}';
    session.messages.add(ChatMessage(id: replyId, text: reply, isUser: false));
    _isAwaitingReply = false;
    _triggerSave();

    // Save chat summary as memory
    _saveChatMemory(session);

    notifyListeners();
    onAIResponse?.call(reply);
  }

  Future<void> _saveChatMemory(ChatSession session) async {
    final messages = session.messages;
    if (messages.length < 2) return;

    final lines = messages.map((m) {
      final role = m.isUser ? 'User' : 'Assistant';
      return '**$role**: ${m.text}';
    });
    final summary = '# Chat: ${session.title}\n\n${lines.join('\n\n')}';
    await _openAIService.saveChatMemory(session.id, summary);
  }

  void _deliverStubReply(ChatSession session) {
    AgentHarness? harness;
    if (session.agentHarnessId != null) {
      try {
        harness = _harnesses.firstWhere((h) => h.id == session.agentHarnessId);
      } catch (_) {}
    }

    Future.delayed(const Duration(milliseconds: 1400), () {
      String reply = '';
      if (harness != null) {
        if (harness.type == AgentHarnessType.connectedHarness) {
          reply =
              'Simulated connection response from remote endpoint: ${harness.connectionUrl}. Request: "${session.messages.last.text}"';
        } else {
          reply =
              'Simulated system agent running with instructions from agent.md (${harness.name}): "Instructions loaded successfully. Working on request: ${session.messages.last.text}"';
        }
      } else {
        reply = _stubReply(session.messages.last.text);
      }

      final replyId = '${session.id}_msg_${session.messages.length}';
      session.messages.add(ChatMessage(id: replyId, text: reply, isUser: false));
      _isAwaitingReply = false;
      _triggerSave();
      notifyListeners();
      onAIResponse?.call(reply);
    });
  }

  String _stubReply(String userText) {
    final stubs = [
      'I received your message: "$userText". Connect an API key in Settings to enable AI responses.',
      'Thanks for your message. To get real AI responses, please configure your API endpoint in Settings.',
      'I understand you said "$userText". Set up your API key in Settings to unlock AI features.',
    ];
    return stubs[Random().nextInt(stubs.length)];
  }

  String _defaultTitle(ChatSessionType type) {
    switch (type) {
      case ChatSessionType.chat:
        return 'New Chat';
      case ChatSessionType.agent:
        return 'New Agent';
      case ChatSessionType.other:
        return 'New Session';
    }
  }
}
