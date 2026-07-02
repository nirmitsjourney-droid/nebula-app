import 'package:flutter/material.dart';

enum ChatSessionType { chat, agent, other }

class FileAttachment {
  FileAttachment({
    required this.name,
    required this.path,
    this.sizeBytes = 0,
  });

  final String name;
  final String path;
  final int sizeBytes;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isTextBased {
    final ext = name.split('.').last.toLowerCase();
    const textExts = {
      'txt', 'md', 'dart', 'js', 'ts', 'py', 'java', 'cpp', 'c', 'h',
      'html', 'css', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg',
      'sh', 'bat', 'ps1', 'sql', 'rb', 'php', 'go', 'rs', 'swift', 'kt',
      'scala', 'clj', 'lua', 'r', 'pl', 'csv', 'env', 'gitignore',
    };
    return textExts.contains(ext);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'sizeBytes': sizeBytes,
      };

  factory FileAttachment.fromJson(Map<String, dynamic> json) => FileAttachment(
        name: json['name'] as String,
        path: json['path'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.imagePath,
    this.fileAttachment,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  String text;
  final bool isUser;
  String? imagePath;
  FileAttachment? fileAttachment;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'imagePath': imagePath,
        if (fileAttachment != null) 'fileAttachment': fileAttachment!.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        text: json['text'] as String,
        isUser: json['isUser'] as bool,
        imagePath: json['imagePath'] as String?,
        fileAttachment: json['fileAttachment'] != null
            ? FileAttachment.fromJson(json['fileAttachment'] as Map<String, dynamic>)
            : null,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

enum AgentHarnessType {
  agentMd,
  connectedHarness,
}

class AgentHarness {
  AgentHarness({
    required this.id,
    required this.name,
    required this.type,
    this.agentMd = '',
    this.connectionUrl = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  AgentHarnessType type;
  String agentMd;
  String connectionUrl;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'agentMd': agentMd,
        'connectionUrl': connectionUrl,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AgentHarness.fromJson(Map<String, dynamic> json) => AgentHarness(
        id: json['id'] as String,
        name: json['name'] as String,
        type: AgentHarnessType.values.byName(json['type'] as String),
        agentMd: json['agentMd'] as String? ?? '',
        connectionUrl: json['connectionUrl'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.type,
    this.agentHarnessId,
    List<ChatMessage>? messages,
    DateTime? createdAt,
  })  : messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  final ChatSessionType type;
  final String? agentHarnessId;
  final List<ChatMessage> messages;
  final DateTime createdAt;

  IconData get icon {
    switch (type) {
      case ChatSessionType.chat:
        return Icons.chat_bubble_outline_rounded;
      case ChatSessionType.agent:
        return Icons.smart_toy_outlined;
      case ChatSessionType.other:
        return Icons.more_horiz_rounded;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'agentHarnessId': agentHarnessId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String,
        type: ChatSessionType.values.byName(json['type'] as String),
        agentHarnessId: json['agentHarnessId'] as String?,
        messages: (json['messages'] as List<dynamic>?)
                ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class AISuggestion {
  const AISuggestion({
    required this.prompt,
    required this.description,
    required this.icon,
    required this.backgroundColor,
  });

  final String prompt;
  final String description;
  final IconData icon;
  final Color backgroundColor;
}
