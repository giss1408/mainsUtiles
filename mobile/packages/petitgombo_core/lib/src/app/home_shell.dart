import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../info/info_screens.dart';
import '../profile/profile_screen.dart';
import '../widgets/ui_kit.dart';
import 'providers.dart';

/// The frame of the signed-in app: the header, the current tab, the bottom bar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.home, required this.onSignOut});

  /// The first tab: the offers, or the verification checklist.
  final Widget home;
  final VoidCallback onSignOut;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(appRoleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(),
        actions: [
          IconButton(
            tooltip: HowItWorksScreen.title,
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => HowItWorksScreen(role: role)),
            ),
          ),
        ],
      ),
      body: _tab == 0 ? widget.home : ProfileScreen(onSignOut: widget.onSignOut),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: ProfileCopy.title,
            ),
          ],
        ),
      ),
    );
  }
}
