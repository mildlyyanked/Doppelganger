import 'package:flutter/material.dart';
import '../main.dart';

/// Configure the backend, create a twin, attach sources, poll, build persona.
/// This is the "wire it up" screen; Chat is where you actually talk.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _url = TextEditingController(text: widget.state.baseUrl);
  late final _subject = TextEditingController(text: widget.state.subjectId);
  late final _key = TextEditingController(text: widget.state.openRouterKey);
  final _redditUser = TextEditingController();
  String _log = '';
  bool _busy = false;
  bool _showKey = false;

  void _append(String s) => setState(() => _log = '$s\n$_log');

  Future<void> _run(String label, Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      _append('✓ $label');
    } catch (e) {
      _append('✗ $label — $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Doppelganger',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text('Build a twin, then talk to it.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'Backend URL',
            helperText: 'Emulator: 10.0.2.2:8000 · Real phone: your LAN IP',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            s.baseUrl = v.trim();
            s.save();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _subject,
          decoration: const InputDecoration(
            labelText: 'Subject id',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            s.subjectId = v.trim();
            s.save();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          decoration: InputDecoration(
            labelText: 'OpenRouter API key',
            helperText: 'Stored on this device; sent to your backend for LLM calls',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
          onChanged: (v) {
            s.openRouterKey = v.trim();
            s.save();
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run('created twin', () async {
                    await s.api.createTwin(s.subjectId, sources: [
                      {
                        'kind': 'upload',
                        'config': {'path': 'sample_data/sample_person.json'}
                      }
                    ]);
                  }),
          icon: const Icon(Icons.person_add),
          label: const Text('Create twin (with sample data)'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _redditUser,
              decoration: const InputDecoration(
                labelText: 'Reddit username (public)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy || _redditUser.text.trim().isEmpty
                ? null
                : () => _run('added reddit source', () async {
                      await s.api.addSource(s.subjectId, 'reddit',
                          {'username': _redditUser.text.trim()});
                    }),
            child: const Text('Add'),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run('polled sources', () async {
                      final r = await s.api.poll(s.subjectId);
                      _append('  memory_count=${r['memory_count']}');
                    }),
            icon: const Icon(Icons.sync),
            label: const Text('Poll now'),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy
                ? null
                : () => _run('built persona', () async {
                      final card = await s.api.buildPersona(s.subjectId);
                      final stats = await s.api.stats(s.subjectId);
                      s.setPersona(
                          (card['display_name'] ?? '') as String,
                          (stats['memory_count'] ?? 0) as int);
                      _append('  persona: ${card['display_name']}');
                    }),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Build persona'),
          ),
        ]),
        const SizedBox(height: 16),
        if (s.personaReady)
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.check_circle),
              title: Text(s.personaName.isEmpty ? s.subjectId : s.personaName),
              subtitle: Text('${s.memoryCount} memories · go to Chat'),
            ),
          ),
        if (_busy) const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        const SizedBox(height: 12),
        if (_log.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_log,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
      ],
    );
  }
}
