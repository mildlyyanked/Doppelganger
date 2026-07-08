import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/twin.dart';
import 'screens/setup_screen.dart';
import 'screens/chat_screen.dart';

void main() => runApp(const DoppelgangerApp());

/// App state for the on-device PoC. No backend: the [Twin] holds the memory
/// store, persona and OpenRouter client, all in memory for the session.
class AppState extends ChangeNotifier {
  String subjectId = 'sample_dad';
  String openRouterKey = ''; // persisted on-device; sent only to OpenRouter

  Twin? twin;
  bool get personaReady => twin?.card != null;
  String get personaName => twin?.card?.displayName ?? '';
  int get memoryCount => twin?.store.count ?? 0;

  /// Create (or recreate) the twin with the current key/subject.
  Twin ensureTwin() {
    final existing = twin;
    if (existing != null && existing.subjectId == subjectId) return existing;
    final t = Twin(subjectId: subjectId, apiKey: openRouterKey);
    twin = t;
    return t;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    subjectId = p.getString('subjectId') ?? subjectId;
    openRouterKey = p.getString('openRouterKey') ?? openRouterKey;
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('subjectId', subjectId);
    await p.setString('openRouterKey', openRouterKey);
  }

  void changed() => notifyListeners();
}

class DoppelgangerApp extends StatefulWidget {
  const DoppelgangerApp({super.key});
  @override
  State<DoppelgangerApp> createState() => _DoppelgangerAppState();
}

class _DoppelgangerAppState extends State<DoppelgangerApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doppelganger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C5CE7),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Home(state: state),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.state});
  final AppState state;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      SetupScreen(state: widget.state),
      ChatScreen(state: widget.state),
    ];
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) => Scaffold(
        body: SafeArea(child: screens[_tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.tune), label: 'Setup'),
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          ],
        ),
      ),
    );
  }
}
