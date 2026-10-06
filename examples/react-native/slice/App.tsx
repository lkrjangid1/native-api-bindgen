/**
 * React Native (New Architecture) example for native-api-bindgen.
 *
 * The Showcase tab does real tasks on Android and iOS — a live device
 * dashboard, text-to-speech, the share sheet, the clipboard, a persistent
 * note, haptics and opening URLs — all through generated bindings: Android
 * calls go TypeScript -> JSI -> C++ runtime -> JNI, iOS calls TypeScript ->
 * JSI -> Objective-C++ runtime -> NSInvocation. There is no hand-written
 * TurboModule per API.
 *
 * On launch the app also runs the platform's self-test suite (Self-tests
 * tab) and logs `NAB_TEST ...` lines, read by tools/run_rn_device_tests.sh
 * from logcat and tools/run_rn_ios_tests.sh from the simulator log.
 */
import React, { useEffect, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

import { ShowcaseScreen } from './src/showcase/ShowcaseScreen';
import { selfTests, type TestResult } from './src/selfTests';
import { registerTestHost } from './src/testHost';

type Tab = 'showcase' | 'tests';

function Screen(): React.JSX.Element {
  const dark = useColorScheme() === 'dark';
  const [tab, setTab] = useState<Tab>('showcase');
  const [results, setResults] = useState<TestResult[]>([]);
  const [done, setDone] = useState(false);
  const [hosted, setHosted] = useState<React.ReactElement | null>(null);

  useEffect(() => registerTestHost(setHosted), []);

  useEffect(() => {
    selfTests(r => setResults(prev => [...prev, r])).then(() => setDone(true));
  }, []);

  const passed = results.filter(r => r.ok).length;
  const text = { color: dark ? '#e8edf5' : '#111827' };
  return (
    <SafeAreaView
      style={[styles.root, dark ? styles.rootDark : styles.rootLight]}
    >
      <Text style={[styles.heading, text]}>Native APIs from JavaScript</Text>
      <View style={styles.tabs}>
        {(
          [
            ['showcase', 'Showcase'],
            [
              'tests',
              `Self-tests ${passed}/${results.length}${done ? '' : '…'}`,
            ],
          ] as const
        ).map(([key, label]) => (
          <Pressable
            key={key}
            onPress={() => setTab(key)}
            style={[styles.tab, tab === key && styles.tabActive]}
          >
            <Text style={[text, tab === key && styles.tabActiveText]}>
              {label}
            </Text>
          </Pressable>
        ))}
      </View>
      {/* Native views used by self-tests are mounted here while they run. */}
      {hosted}
      {tab === 'showcase' ? (
        <ShowcaseScreen />
      ) : (
        <ScrollView contentContainerStyle={styles.results}>
          {results.map(r => (
            <Text key={r.name} style={r.ok ? styles.pass : styles.fail}>
              {r.ok ? 'PASS' : 'FAIL'} {r.name}
              {r.error ? ` — ${r.error}` : ''}
            </Text>
          ))}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  rootDark: { backgroundColor: '#0d1117' },
  rootLight: { backgroundColor: '#ffffff' },
  heading: {
    fontSize: 22,
    fontWeight: '700',
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  tabs: { flexDirection: 'row', gap: 8, paddingHorizontal: 16, paddingTop: 12 },
  tab: { paddingVertical: 6, paddingHorizontal: 12, borderRadius: 16 },
  tabActive: { backgroundColor: '#4338ca' },
  tabActiveText: { color: '#ffffff' },
  results: { padding: 16, gap: 4 },
  pass: { color: '#1b8a3a' },
  fail: { color: '#c62828' },
});

function App(): React.JSX.Element {
  return (
    <SafeAreaProvider>
      <Screen />
    </SafeAreaProvider>
  );
}

export default App;
