import 'package:flutter/material.dart';

import 'screens/analyze_screen.dart';
import 'screens/live_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_settings.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const TennisFormApp());
}

class TennisFormApp extends StatelessWidget {
  const TennisFormApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tennis Form Coach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  final AppSettings _settings = AppSettings();

  @override
  Widget build(BuildContext context) {
    final pages = [
      LiveScreen(settings: _settings),
      AnalyzeScreen(settings: _settings),
      SettingsScreen(settings: _settings),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.sports_tennis, color: AppTheme.courtGreen, size: 32),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.videocam_outlined),
                selectedIcon: Icon(Icons.videocam),
                label: Text('Live'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: Text('Analyze Video'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),
        ],
      ),
    );
  }
}
