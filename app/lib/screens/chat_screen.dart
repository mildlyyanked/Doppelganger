import 'package:flutter/material.dart';
import '../main.dart';

class _Msg {
  _Msg(this.text, this.fromUser);
  String text;
  final bool fromUser;
}

/// The conversation with the twin. Streams the reply token-by-token.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _streaming = false;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _streaming) return;
    _input.clear();

    // Build history from prior turns before adding the new one.
    final history = <Map<String, String>>[
      for (final m in _msgs)
        {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}
    ];

    setState(() {
      _msgs.add(_Msg(text, true));
      _msgs.add(_Msg('', false));
      _streaming = true;
    });
    _toBottom();

    final reply = _msgs.last;
    try {
      await for (final delta
          in widget.state.api.chatStream(widget.state.subjectId, text, history)) {
        setState(() => reply.text += delta);
        _toBottom();
      }
    } catch (e) {
      setState(() => reply.text =
          reply.text.isEmpty ? '⚠ $e' : '${reply.text}\n\n⚠ $e');
    } finally {
      setState(() => _streaming = false);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (!s.personaReady) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Build a persona on the Setup tab first.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(child: Text((s.personaName.isEmpty ? '?' : s.personaName)[0])),
            const SizedBox(width: 12),
            Text(s.personaName.isEmpty ? s.subjectId : s.personaName,
                style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (context, i) => _bubble(_msgs[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Say something...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _streaming ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _bubble(_Msg m) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: m.fromUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          m.text.isEmpty ? '…' : m.text,
          style: TextStyle(
              color: m.fromUser ? scheme.onPrimary : scheme.onSurface),
        ),
      ),
    );
  }
}
