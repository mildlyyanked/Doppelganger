import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/sources.dart';
import '../main.dart';

/// On-device setup: paste your key, pull in sources (live or imported), then
/// build the persona. Everything runs in the app — no backend.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _subject = TextEditingController(text: widget.state.subjectId);
  late final _key = TextEditingController(text: widget.state.openRouterKey);
  String _log = '';
  bool _busy = false;
  bool _showKey = false;

  void _append(String s) => setState(() => _log = '$s\n$_log');

  Future<void> _run(String label, Future<int> Function() fn) async {
    setState(() => _busy = true);
    try {
      final n = await fn();
      _append('✓ $label${n >= 0 ? ' (+$n memories, ${widget.state.memoryCount} total)' : ''}');
      widget.state.changed();
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
        Text('Doppelganger', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text('On-device PoC — build a twin, then talk to it.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          decoration: InputDecoration(
            labelText: 'OpenRouter API key',
            helperText: 'Stored on this device; sent only to OpenRouter',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
          onChanged: (v) {
            s.openRouterKey = v.trim();
            s.twin = null; // recreate with the new key on next use
            s.save();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _subject,
          decoration: const InputDecoration(
            labelText: 'Subject id / name',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            s.subjectId = v.trim();
            s.save();
          },
        ),
        const SizedBox(height: 20),
        Text('Sources', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run('loaded sample',
                    () async => s.ensureTwin().addMemories(await Sources.loadSample())),
            icon: const Icon(Icons.person_add),
            label: const Text('Sample person'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _addReddit,
            icon: const Icon(Icons.forum),
            label: const Text('Reddit user'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _addWeb,
            icon: const Icon(Icons.link),
            label: const Text('Web URL'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importExport,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import export'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Live: Reddit, Web. Import-only (paste your data export): '
          'X/Twitter, Instagram, Facebook, LinkedIn — these block scraping, so '
          'their "Download Your Data" dump is the reliable, higher-fidelity path.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _busy || s.memoryCount == 0
              ? null
              : () => _run('built persona', () async {
                    final card = await s.ensureTwin().buildPersona();
                    _append('  persona: ${card.displayName}');
                    return -1;
                  }),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Build persona'),
        ),
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
        if (_busy)
          const Padding(
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

  Future<void> _addReddit() async {
    final user = await _prompt('Reddit username', 'e.g. spez (public profile)');
    if (user == null || user.isEmpty) return;
    await _run('added reddit u/$user',
        () async => widget.state.ensureTwin().addMemories(await Sources.reddit(user)));
  }

  Future<void> _addWeb() async {
    final url = await _prompt('Article / page URL', 'https://...');
    if (url == null || url.isEmpty) return;
    await _run('added web page',
        () async => widget.state.ensureTwin().addMemories(await Sources.web(url)));
  }

  Future<void> _importExport() async {
    final result = await showDialog<_ImportResult>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (result == null || result.json.trim().isEmpty) return;
    await _run('imported ${result.platform.label}', () async {
      final items = Sources.importJson(result.json, result.platform);
      return widget.state.ensureTwin().addMemories(items);
    });
  }

  Future<String?> _prompt(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
  }
}

class _ImportResult {
  _ImportResult(this.platform, this.json);
  final Platform platform;
  final String json;
}

/// Paste a JSON array of posts (from a data export) and tag its platform.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _c = TextEditingController();
  Platform _platform = Platform.x;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import posts'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<Platform>(
            value: _platform,
            decoration: const InputDecoration(labelText: 'Platform'),
            items: [
              Platform.x,
              Platform.instagram,
              Platform.facebook,
              Platform.linkedin,
              Platform.youtube,
              Platform.upload,
            ]
                .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (p) => setState(() => _platform = p ?? Platform.x),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  '[{"text": "...", "created_at": "2024-01-01"}, ...]',
              helperText: 'JSON array of posts (text/caption/body + created_at)',
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _ImportResult(_platform, _c.text)),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
