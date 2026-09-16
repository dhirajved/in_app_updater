import 'package:flutter/material.dart';
import 'package:in_app_updater/in_app_updater.dart';

import 'manual_update_flow_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Pattern 1 (recommended for most apps): wrap your home screen in
    // UpdateChecker. It calls checkForUpdate() once right after launch and
    // shows a built-in dialog + (on Android) a "restart to install" snackbar
    // automatically — no wiring required. See ManualUpdateFlowPage below for
    // the alternative: driving every step yourself.
    return const MaterialApp(home: UpdateChecker(child: HomePage()));
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _updateService = NativeUpdateService();
  String _lastResult = 'Tap the button to call the native update check.';

  Future<void> _checkForUpdate() async {
    try {
      final result = await _updateService.checkForUpdate();
      setState(() => _lastResult = _describe(result));
    } catch (e) {
      setState(() => _lastResult = 'checkForUpdate failed: $e');
    }
  }

  String _describe(UpdateCheckResult result) =>
      'updateAvailable: ${result.updateAvailable}\n'
      'immediateAllowed: ${result.immediateAllowed}\n'
      'flexibleAllowed: ${result.flexibleAllowed}\n'
      'currentVersion: ${result.currentVersion}\n'
      'latestVersion: ${result.latestVersion}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('in_app_updater example')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pattern 1 — UpdateChecker (already wraps this screen in '
              'MyApp and ran automatically on launch; see the Android '
              'snackbar / iOS dialog if a real update is live).\n\n'
              'Tap below to call the native side directly and see the raw '
              'result:',
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkForUpdate,
              child: const Text('Check for update'),
            ),
            const SizedBox(height: 16),
            Text(_lastResult),
            const Divider(height: 48),
            const Text(
              'Pattern 2 — build your own UI/flow with NativeUpdateService '
              'directly (custom dialog, your own state management, checking '
              'from somewhere other than app launch, etc).',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ManualUpdateFlowPage(),
                ),
              ),
              child: const Text('Open manual-flow example'),
            ),
          ],
        ),
      ),
    );
  }
}
