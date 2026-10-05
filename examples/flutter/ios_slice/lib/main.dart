import 'package:flutter/material.dart';

import 'slice.dart';

void main() => runApp(const SliceApp());

/// Shows values obtained through the generated iOS bindings.
class SliceApp extends StatelessWidget {
  const SliceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final summary = deviceSummary();
    return MaterialApp(
      title: 'native-api-bindgen iOS slice',
      home: Scaffold(
        appBar: AppBar(title: const Text('iOS slice')),
        body: ListView(
          children: [
            for (final e in summary.entries)
              ListTile(title: Text(e.key), subtitle: Text(e.value)),
            ListTile(
              title: const Text('UIView subviews'),
              subtitle: Text('${buildViews()}'),
            ),
            ListTile(
              title: const Text('NSError → NativeObjCError'),
              subtitle: Text(listMissingDirectory() ?? 'no error'),
            ),
          ],
        ),
      ),
    );
  }
}
