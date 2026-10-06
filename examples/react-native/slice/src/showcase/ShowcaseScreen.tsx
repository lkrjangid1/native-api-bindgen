/**
 * Showcase screen: a live device dashboard and real tasks, each done through
 * generated bindings (Android: JSI -> JNI, iOS: JSI -> Objective-C++).
 */
import React, { useCallback, useEffect, useState } from 'react';
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  useColorScheme,
} from 'react-native';

import * as android from './android';
import * as ios from './ios';

type Meter = { label: string; value: number | null; detail: string };
type Status = {
  title: string;
  subtitle: string;
  meters: Meter[];
  facts: string[];
};
type Task = { title: string; api: string; run: (text: string) => unknown };

const gb = (bytes: number) => `${(bytes / 2 ** 30).toFixed(1)} GB`;

function readStatus(): Status {
  if (Platform.OS === 'android') {
    const s = android.deviceStatus();
    const usedMem = s.totalMemBytes - s.availMemBytes;
    const usedDisk = s.totalStorageBytes - s.freeStorageBytes;
    return {
      title: s.device,
      subtitle: `Android API ${s.apiLevel}`,
      meters: [
        {
          label: 'Battery',
          value: s.batteryPercent === null ? null : s.batteryPercent / 100,
          detail:
            s.batteryPercent === null
              ? 'unknown'
              : `${s.batteryPercent}%${s.charging ? ' · charging' : ''}`,
        },
        {
          label: 'Memory',
          value: usedMem / s.totalMemBytes,
          detail: `${gb(usedMem)} of ${gb(s.totalMemBytes)} used${
            s.lowMemory ? ' · LOW' : ''
          }`,
        },
        {
          label: 'Storage',
          value: usedDisk / s.totalStorageBytes,
          detail: `${gb(s.freeStorageBytes)} free of ${gb(
            s.totalStorageBytes,
          )}`,
        },
      ],
      facts: [`Network: ${s.network}`],
    };
  }
  const s = ios.deviceStatus();
  const { freeStorageBytes: free, totalStorageBytes: total } = s;
  const hours = Math.floor(s.uptimeSeconds / 3600);
  const minutes = Math.floor((s.uptimeSeconds % 3600) / 60);
  return {
    title: s.device,
    subtitle: s.system,
    meters: [
      {
        label: 'Battery',
        value: s.batteryLevel,
        detail:
          s.batteryLevel === null
            ? 'not reported (simulator)'
            : `${Math.round(s.batteryLevel * 100)}% · ${s.batteryState}`,
      },
      {
        label: 'Storage',
        value: free === null || total === null ? null : (total - free) / total,
        detail:
          free === null || total === null
            ? 'unknown'
            : `${gb(free)} free of ${gb(total)}`,
      },
    ],
    facts: [
      `Thermal: ${s.thermalState}`,
      `${gb(s.physicalMemoryBytes)} RAM`,
      `${s.processors} cores`,
      `Up ${hours} h ${minutes} min`,
      `Low Power Mode ${s.lowPowerMode ? 'on' : 'off'}`,
    ],
  };
}

const androidTasks: Task[] = [
  {
    title: 'Speak',
    api: 'TextToSpeech + OnInitListener implemented in JS',
    run: async text => {
      await android.speak(text);
      return 'Speaking…';
    },
  },
  {
    title: 'Share',
    api: 'Intent.ACTION_SEND + Intent.createChooser',
    run: text => {
      android.share(text);
      return 'Chooser opened';
    },
  },
  {
    title: 'Copy, then paste back',
    api: 'ClipboardManager + ClipData',
    run: text => {
      android.copy(text);
      return `Clipboard now holds: ${android.paste()}`;
    },
  },
  {
    title: 'Save as note',
    api: 'SharedPreferences.Editor (survives restarts)',
    run: text => {
      android.saveNote(text);
      return 'Note saved';
    },
  },
  {
    title: 'Vibrate',
    api: 'Vibrator + VibrationEffect (API 26+, runtime-guarded)',
    run: () => android.vibrate(),
  },
  {
    title: 'Location settings',
    api: 'Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)',
    run: () => {
      android.openLocationSettings();
      return 'Location settings opened';
    },
  },
  {
    title: 'App permissions (location)',
    api: 'Settings.ACTION_APPLICATION_DETAILS_SETTINGS + package: URI',
    run: () => {
      android.openAppPermissions();
      return 'App settings opened';
    },
  },
  {
    title: 'Open Android reference',
    api: 'Intent.ACTION_VIEW + Activity.startActivity',
    run: () => {
      android.openUrl('https://developer.android.com/reference');
      return 'Browser opened';
    },
  },
];

const iosTasks: Task[] = [
  {
    title: 'Speak',
    api: 'AVSpeechSynthesizer + AVSpeechUtterance',
    run: text => {
      ios.speak(text);
      return 'Speaking…';
    },
  },
  {
    title: 'Share',
    api: 'UIActivityViewController, presented from the key window',
    run: async text => {
      await ios.share(text);
      return 'Share sheet presented';
    },
  },
  {
    title: 'Copy, then paste back',
    api: 'UIPasteboard.generalPasteboard',
    run: text => {
      ios.copy(text);
      return `Pasteboard now holds: ${ios.paste()}`;
    },
  },
  {
    title: 'Save as note',
    api: 'NSUserDefaults (survives restarts)',
    run: text => {
      ios.saveNote(text);
      return 'Note saved';
    },
  },
  {
    title: 'Haptics',
    api: 'UIImpactFeedbackGenerator + UINotificationFeedbackGenerator',
    run: async () => {
      await ios.haptics();
      return 'Impact, then success';
    },
  },
  {
    title: 'App settings (location permission)',
    api: 'UIApplicationOpenSettingsURLString via openURL:',
    run: async () =>
      (await ios.openAppSettings())
        ? 'Settings opened'
        : 'Could not open Settings',
  },
  {
    title: 'Open Apple documentation',
    api: 'UIApplication openURL:options:completionHandler: (block → JS)',
    run: async () =>
      (await ios.openUrl('https://developer.apple.com/documentation/uikit'))
        ? 'Opened in Safari'
        : 'Could not open the URL',
  },
];

export function ShowcaseScreen(): React.JSX.Element {
  const dark = useColorScheme() === 'dark';
  const c = dark ? darkColors : lightColors;
  const [status, setStatus] = useState<Status | null>(null);
  const [text, setText] = useState(
    'Hello from JavaScript, through generated native bindings.',
  );
  const [message, setMessage] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  const refresh = useCallback(() => {
    try {
      setStatus(readStatus());
    } catch (e) {
      setMessage(`Status failed: ${String(e)}`);
    }
  }, []);

  useEffect(() => {
    refresh();
    setNote(Platform.OS === 'android' ? android.loadNote() : ios.loadNote());
    const timer = setInterval(refresh, 3000);
    return () => clearInterval(timer);
  }, [refresh]);

  const tasks = Platform.OS === 'android' ? androidTasks : iosTasks;
  const run = async (task: Task) => {
    try {
      const result = await task.run(text);
      setMessage(typeof result === 'string' ? result : `${task.title}: done`);
      if (task.title === 'Save as note') {
        setNote(
          Platform.OS === 'android' ? android.loadNote() : ios.loadNote(),
        );
      }
    } catch (e) {
      setMessage(`${task.title} failed: ${String(e)}`);
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.content}>
      {status && (
        <View style={[styles.card, { backgroundColor: c.card }]}>
          <Text style={[styles.title, { color: c.text }]}>{status.title}</Text>
          <Text style={[styles.small, { color: c.muted }]}>
            {status.subtitle} · refreshes every 3 s
          </Text>
          {status.meters.map(m => (
            <View key={m.label} style={styles.meter}>
              <View style={styles.meterHead}>
                <Text style={{ color: c.text }}>{m.label}</Text>
                <Text style={[styles.small, { color: c.muted }]}>
                  {m.detail}
                </Text>
              </View>
              <View style={[styles.track, { backgroundColor: c.track }]}>
                <View
                  style={[
                    styles.fill,
                    {
                      backgroundColor: c.accent,
                      width: `${Math.round((m.value ?? 0) * 100)}%`,
                    },
                  ]}
                />
              </View>
            </View>
          ))}
          <View style={styles.facts}>
            {status.facts.map(f => (
              <Text
                key={f}
                style={[styles.fact, { color: c.text, borderColor: c.track }]}
              >
                {f}
              </Text>
            ))}
          </View>
        </View>
      )}

      <TextInput
        value={text}
        onChangeText={setText}
        multiline
        style={[styles.input, { color: c.text, borderColor: c.muted }]}
        accessibilityLabel="Text used by the tasks"
      />
      {message && (
        <Text style={[styles.message, { color: c.accent }]}>{message}</Text>
      )}

      {tasks.map(task => (
        <Pressable
          key={task.title}
          onPress={() => run(task)}
          style={({ pressed }) => [
            styles.card,
            styles.task,
            { backgroundColor: c.card, opacity: pressed ? 0.6 : 1 },
          ]}
        >
          <View style={styles.taskText}>
            <Text style={[styles.taskTitle, { color: c.text }]}>
              {task.title}
            </Text>
            <Text style={[styles.small, { color: c.muted }]}>{task.api}</Text>
            {task.title === 'Save as note' && (
              <Text style={[styles.small, { color: c.muted }]}>
                {note === null ? 'No note saved yet' : `Saved: ${note}`}
              </Text>
            )}
          </View>
          <Text style={[styles.play, { color: c.accent }]}>▶</Text>
        </Pressable>
      ))}
    </ScrollView>
  );
}

const lightColors = {
  card: '#f1f4f9',
  text: '#111827',
  muted: '#5b6474',
  track: '#d9e0ea',
  accent: '#4338ca',
};
const darkColors = {
  card: '#1b2230',
  text: '#e8edf5',
  muted: '#9aa6b8',
  track: '#2d3748',
  accent: '#a5b4fc',
};

const styles = StyleSheet.create({
  content: { padding: 16, gap: 12 },
  card: { borderRadius: 16, padding: 16 },
  title: { fontSize: 20, fontWeight: '600' },
  small: { fontSize: 12 },
  meter: { marginTop: 12 },
  meterHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  track: { height: 6, borderRadius: 3, overflow: 'hidden' },
  fill: { height: 6 },
  facts: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 12 },
  fact: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 8,
    paddingVertical: 4,
    fontSize: 13,
  },
  input: { borderWidth: 1, borderRadius: 8, padding: 12, fontSize: 15 },
  message: { fontSize: 13 },
  task: { flexDirection: 'row', alignItems: 'center' },
  taskText: { flex: 1, gap: 2 },
  taskTitle: { fontSize: 16, fontWeight: '500' },
  play: { fontSize: 18, marginLeft: 12 },
});
