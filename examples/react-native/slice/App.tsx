/**
 * React Native (New Architecture) example for native-api-bindgen.
 *
 * Android calls go through bindings generated from android.jar
 * (TypeScript -> JSI -> C++ runtime -> JNI); iOS calls through bindings
 * generated from the Xcode SDK headers (TypeScript -> JSI -> Objective-C++
 * runtime -> NSInvocation). There is no hand-written TurboModule per API.
 *
 * On launch the app runs the platform's self-test suite and logs
 * `NAB_TEST ...` lines (read by tools/run_rn_device_tests.sh from logcat and
 * tools/run_rn_ios_tests.sh from the simulator log).
 */
import React, { useEffect, useState } from 'react';
import {
  Button,
  Platform,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { selfTests, type TestResult } from './src/selfTests';
import { registerTestHost } from './src/testHost';
import { Intent, Uri, currentActivity } from './native-api-bindings';
import { UIDevice } from './native-api-bindings/ios';

function App(): React.JSX.Element {
  const [results, setResults] = useState<TestResult[]>([]);
  const [done, setDone] = useState(false);
  const [hosted, setHosted] = useState<React.ReactElement | null>(null);

  useEffect(() => registerTestHost(setHosted), []);

  useEffect(() => {
    selfTests(r => setResults(prev => [...prev, r])).then(() => setDone(true));
  }, []);

  const passed = results.filter(r => r.ok).length;
  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>native-api-bindgen · React Native</Text>
      <Text>
        {done ? 'Finished' : 'Running'}: {passed}/{results.length} passed
      </Text>
      {Platform.OS === 'ios' ? (
        <Text style={styles.row}>
          {UIDevice.currentDevice.systemName}{' '}
          {UIDevice.currentDevice.systemVersion} ·{' '}
          {UIDevice.currentDevice.model}
        </Text>
      ) : (
        <View style={styles.row}>
          <Button
            title="Open developer.android.com"
            onPress={() => {
              const activity = currentActivity();
              if (activity === null) return;
              const intent = Intent.new$String$Uri(
                Intent.ACTION_VIEW,
                Uri.parse('https://developer.android.com/'),
              );
              activity.startActivity(intent);
              intent.release();
            }}
          />
        </View>
      )}
      {hosted}
      <ScrollView>
        {results.map(r => (
          <Text key={r.name} style={r.ok ? styles.pass : styles.fail}>
            {r.ok ? 'PASS' : 'FAIL'} {r.name}
            {r.error ? ` — ${r.error}` : ''}
          </Text>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, padding: 16 },
  title: { fontSize: 18, fontWeight: '600', marginBottom: 8 },
  row: { marginVertical: 8 },
  pass: { color: '#1b5e20' },
  fail: { color: '#b71c1c' },
});

export default App;
