import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../services/chat_manager.dart';

/// A Material 3 Expressive Dialog to create a new Agent Harness configuration.
class CreateAgentDialog extends StatefulWidget {
  const CreateAgentDialog({super.key, required this.chatManager});

  final ChatManager chatManager;

  /// Helper to show this dialog.
  static Future<void> show(BuildContext context, ChatManager chatManager) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateAgentDialog(chatManager: chatManager),
    );
  }

  @override
  State<CreateAgentDialog> createState() => _CreateAgentDialogState();
}

class _CreateAgentDialogState extends State<CreateAgentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _markdownController = TextEditingController(
    text: '# Agent Configuration\n\n'
        '## Profile\n'
        'Name: Custom Device Agent\n'
        'Role: Assist with files and system calls.\n\n'
        '## System Rules\n'
        '1. Be direct and concise.\n'
        '2. Confirm actions before writing files.\n',
  );
  final _urlController = TextEditingController(text: 'http://localhost:8080/agent/harness');

  AgentHarnessType _harnessType = AgentHarnessType.agentMd;

  @override
  void dispose() {
    _nameController.dispose();
    _markdownController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final agentMd = _harnessType == AgentHarnessType.agentMd ? _markdownController.text : '';
    final connectionUrl = _harnessType == AgentHarnessType.connectedHarness ? _urlController.text.trim() : '';

    // Create the harness
    final harness = widget.chatManager.createHarness(
      name: name,
      type: _harnessType,
      agentMd: agentMd,
      connectionUrl: connectionUrl,
    );

    // Open a new chat session immediately associated with this harness
    widget.chatManager.createSession(
      type: ChatSessionType.agent,
      agentHarnessId: harness.id,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.smart_toy_outlined, color: colors.primary, size: 28),
          const SizedBox(width: 12),
          const Text('New Agent Harness'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Agent name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Agent Name',
                    hintText: 'e.g. File Manager, Terminal Assistant',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name for the agent';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                Text(
                  'Harness Strategy',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),

                // Strategy selectors (SegmentedButton style but solid colored buttons)
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('agent.md file')),
                        selected: _harnessType == AgentHarnessType.agentMd,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _harnessType = AgentHarnessType.agentMd);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('External URL')),
                        selected: _harnessType == AgentHarnessType.connectedHarness,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _harnessType = AgentHarnessType.connectedHarness);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Form fields depending on harness strategy selection
                if (_harnessType == AgentHarnessType.agentMd) ...[
                  Text(
                    'Markdown Instructions (agent.md)',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _markdownController,
                    maxLines: 8,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '# System Prompt...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Remote Connection Endpoint',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint URL',
                      hintText: 'http://ip-address:port/harness',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_harnessType == AgentHarnessType.connectedHarness) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please specify the remote endpoint URL';
                        }
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create Harness'),
        ),
      ],
    );
  }
}
