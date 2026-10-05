import 'package:flutter/material.dart';

import 'src/slice.dart';

void main() => runApp(const SliceApp());

/// Demo app for the Android vertical slice of native-api-bindgen.
class SliceApp extends StatelessWidget {
  /// Creates the app.
  const SliceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'native-api-bindgen slice',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const SliceHome(),
  );
}

/// Buttons that each exercise one generated Android binding.
class SliceHome extends StatefulWidget {
  /// Creates the page.
  const SliceHome({super.key});

  @override
  State<SliceHome> createState() => _SliceHomeState();
}

class _SliceHomeState extends State<SliceHome> {
  final _log = <String>[];

  void _add(String line) => setState(() => _log.insert(0, line));

  Future<void> _guarded(String label, Future<String> Function() body) async {
    try {
      _add('$label → ${await body()}');
    } on Object catch (e) {
      _add('$label failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(String, Future<String> Function())>[
      ('Context.getPackageName', () async => Slice.packageName()),
      ('Intent + Uri', () async {
        final r = Slice.viewIntent('https://developer.android.com/reference');
        return '${r.action} ${r.data}';
      }),
      ('Bundle put/get', () async => '${Slice.bundleRoundTrip()}'),
      ('Handler.post(Runnable)', Slice.postToMainLooper),
      ('Activity.getLocalClassName', () async => '${Slice.activityClassName()}'),
      ('Activity.startActivity', () async {
        Slice.openUrl('https://developer.android.com/');
        return 'started';
      }),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Android API ${Slice.sdkInt() ?? '?'} via generated bindings')),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, run) in actions)
                FilledButton.tonal(onPressed: () => _guarded(label, run), child: Text(label)),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [for (final l in _log) ListTile(dense: true, title: Text(l))],
            ),
          ),
        ],
      ),
    );
  }
}
