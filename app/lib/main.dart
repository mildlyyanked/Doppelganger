import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'screens/setup_screen.dart';
import 'screens/chat_screen.dart';

void main() => runApp(const DoppelgangerApp());

/// Shared app state for the PoC. Small enough that setState + a passed-down
/// object beats pulling in a state-management package.
class AppState extends ChangeNotifier {
  String baseUrl = 'http://10.0.2.2:8000'; // Android emulator -> host loopback
  String subjectId = 'sample_dad';
  bool personaReady = false;
  String personaName = '';
  int memoryCount = 0;

  ApiClient get api => ApiClient(baseUrl);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? baseUrl;
    subjectId = p.getString('subjectId') ?? subjectId;
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
    await p.setString('subjectId', subjectId);
  }

  void setPersona(String name, int count) {
    personaReady = true;
    personaName = name;
    memoryCount = count;
    notifyListeners();
  }
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
