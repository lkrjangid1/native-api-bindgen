/**
 * On-device self-tests for the generated React Native Android bindings.
 * Each result is logged as `NAB_TEST PASS <name>` / `NAB_TEST FAIL <name>: <error>`,
 * followed by `NAB_TEST DONE pass=<n> fail=<n>`.
 */
import React from 'react';

import {
  AndroidApi,
  Arrays,
  Bundle,
  Greeter,
  Handler,
  Handler_Callback,
  Intent,
  Intent$Flag,
  Looper,
  NativeApiUnavailableError,
  NativeCallbacks,
  NativeView,
  Runnable,
  TextView,
  Uri,
  applicationContext,
  currentActivity,
  isNativeJavaError,
} from '../native-api-bindings';

import { benchmarks } from './bench';
import { showInTestHost } from './testHost';
import type { TestResult } from './testResult';

function expectEqual<T>(actual: T, expected: T, what = 'value'): void {
  if (actual !== expected) {
    throw new Error(
      `${what}: expected ${String(expected)}, got ${String(actual)}`,
    );
  }
}

function expectThrows(
  fn: () => unknown,
  check: (e: unknown) => boolean,
  what: string,
): void {
  try {
    fn();
  } catch (e) {
    if (!check(e)) throw new Error(`${what}: unexpected error ${String(e)}`);
    return;
  }
  throw new Error(`${what}: expected an error`);
}

function withTimeout<T>(p: Promise<T>, ms = 10000): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`timeout after ${ms} ms`)), ms),
    ),
  ]);
}

const tests: Array<[string, () => void | Promise<void>]> = [
  [
    'Context: package name and API level',
    () => {
      expectEqual(
        applicationContext().getPackageName(),
        'com.nabrnslice',
        'packageName',
      );
      if (AndroidApi.sdkInt < 24)
        throw new Error(`sdkInt ${AndroidApi.sdkInt}`);
    },
  ],

  [
    'Intent + Uri: overloaded constructor, constants, nullable setter',
    () => {
      const intent = Intent.new$String$Uri(
        Intent.ACTION_VIEW,
        Uri.parse('https://example.com/path?q=1'),
      );
      expectEqual(intent.getAction(), 'android.intent.action.VIEW', 'action');
      expectEqual(
        intent.getData()?.toString(),
        'https://example.com/path?q=1',
        'data',
      );
      intent.setData(null);
      expectEqual(intent.getData(), null, 'cleared data');
      expectEqual(
        intent.setAction('a.b.C').getAction(),
        'a.b.C',
        'chained setter',
      );
    },
  ],

  [
    'Typed @IntDef constants pass as raw values',
    () => {
      const intent = Intent.new();
      intent.setFlags(
        Intent$Flag.FLAG_ACTIVITY_NEW_TASK | Intent$Flag.FLAG_ACTIVITY_CLEAR_TOP,
      );
      expectEqual(
        intent.getFlags(),
        Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP,
        'flags',
      );
    },
  ],

  [
    'byte[] crosses as Uint8Array (and number[])',
    () => {
      const copy = Arrays.copyOf(new Uint8Array([1, 2, 255, 0]), 3);
      expectEqual(copy instanceof Uint8Array, true, 'Uint8Array result');
      expectEqual(Array.from(copy).join(), '1,2,255', 'bytes');
      const view = new Uint8Array([9, 8, 7, 6]).subarray(1, 3);
      expectEqual(Array.from(Arrays.copyOf(view, 2)).join(), '8,7', 'subarray');
      expectEqual(Array.from(Arrays.copyOf([5, 6], 2)).join(), '5,6', 'number[]');
    },
  ],

  [
    'native UI: a TextView created through bindings is shown',
    async () => {
      const tv = TextView.new(applicationContext());
      tv.setText$CharSequence('Hello native');
      showInTestHost(
        React.createElement(NativeView, {
          view: tv,
          style: { width: 200, height: 48 },
        }),
      );
      for (let i = 0; i < 100 && !tv.isAttachedToWindow(); i++) {
        await new Promise<void>(r => setTimeout(() => r(), 20));
      }
      const attached = tv.isAttachedToWindow();
      const text = tv.getText()?.toString();
      showInTestHost(null);
      expectEqual(attached, true, 'attached to window');
      expectEqual(text, 'Hello native', 'text');
    },
  ],

  [
    'Bean properties delegate to the native getters',
    () => {
      const uri = Uri.parse('https://example.com/p?q=1');
      expectEqual(uri?.scheme, 'https', 'scheme');
      expectEqual(uri?.host, 'example.com', 'host');
      const intent = Intent.new();
      expectEqual(intent.data, null, 'no data');
      intent.setData(uri);
      expectEqual(intent.data?.toString(), 'https://example.com/p?q=1', 'data');
    },
  ],

  [
    'Kotlin suspend functions resolve Promises',
    async () => {
      const g = Greeter.create('Ada');
      expectEqual(await g.greetLater(20n), 'Later, Ada', 'suspended result');
      expectEqual(await g.immediate(), 3, 'direct result');
      expectEqual(await g.maybe(false), null, 'nullable result');
      expectEqual(await g.pause(5n), undefined, 'Unit result');
      const child = await g.child('!');
      expectEqual(child.greet(), 'Hello, Ada!', 'object result');
      let failed: unknown = null;
      try {
        await g.failLater('boom');
      } catch (e) {
        failed = e;
      }
      if (!isNativeJavaError(failed)) {
        throw new Error(`expected NativeJavaError, got ${String(failed)}`);
      }
      const all = await Promise.all(
        Array.from({length: 20}, (_, i) => g.greetLater(BigInt(i % 5))),
      );
      expectEqual(new Set(all).size, 1, 'concurrent results');
    },
  ],

  [
    'Intent.putExtra overloads reach distinct Java methods (incl. bigint long)',
    () => {
      const intent = Intent.new();
      intent.putExtra('i', 7);
      intent.putExtra$String$boolean('b', true);
      intent.putExtra$String$String('s', 'text');
      intent.putExtra$String$long('l', 2n ** 40n);
      expectEqual(intent.getIntExtra('i', -1), 7, 'int');
      expectEqual(intent.getBooleanExtra('b', false), true, 'boolean');
      expectEqual(intent.getStringExtra('s'), 'text', 'String');
      expectEqual(intent.getLongExtra('l', 0n), 2n ** 40n, 'long');
      expectEqual(intent.getIntExtra('missing', -1), -1, 'missing');
    },
  ],

  [
    'Bundle (inherits BaseBundle): put/get, null for missing keys',
    () => {
      const b = Bundle.new();
      b.putString('greeting', 'hello from JS');
      b.putInt('n', 41);
      expectEqual(b.getString('greeting'), 'hello from JS', 'present');
      expectEqual(b.getString('absent'), null, 'absent');
      expectEqual(b.getInt('n'), 41, 'int');
      expectEqual(b.size(), 2, 'size');
    },
  ],

  [
    'Activity: inherited Context methods on the current Activity',
    () => {
      const activity = currentActivity();
      if (activity === null) throw new Error('no current activity');
      expectEqual(
        activity.getLocalClassName(),
        'MainActivity',
        'localClassName',
      );
      expectEqual(
        activity.getPackageName(),
        'com.nabrnslice',
        'inherited getPackageName',
      );
    },
  ],

  [
    'Promise variants run JNI off the JS thread',
    async () => {
      const uri = await withTimeout(Uri.parseAsync('content://x/y'));
      expectEqual(uri?.toString(), 'content://x/y', 'parseAsync');
      const intent = Intent.new$String('act');
      expectEqual(
        await withTimeout(intent.getActionAsync()),
        'act',
        'getActionAsync',
      );
    },
  ],

  [
    'Handler.post(Runnable): JS callback runs from the main Looper',
    async () => {
      const ran = new Promise<string>(resolve => {
        const handler = Handler.new$Looper(Looper.getMainLooper()!);
        const task = Runnable.implement(
          { run: () => resolve('ran') },
          { async: ['run'] },
        );
        handler.post(task);
        task.release(); // Java still holds the proxy; the callback must still arrive
      });
      expectEqual(await withTimeout(ran), 'ran', 'runnable');
    },
  ],

  [
    'Handler.Callback: value-returning callback (main thread waits for JS)',
    async () => {
      const what = await withTimeout(
        new Promise<number>(resolve => {
          const cb = Handler_Callback.implement({
            handleMessage: msg => {
              resolve(msg.what);
              return true;
            },
          });
          const handler = Handler.new$Looper$Callback(
            Looper.getMainLooper()!,
            cb,
          );
          expectEqual(handler.sendEmptyMessage(42), true, 'sendEmptyMessage');
        }),
      );
      expectEqual(what, 42, 'message.what');
    },
  ],

  [
    'A throwing void callback is reported and does not crash the app',
    async () => {
      const reported = new Promise<string>(resolve => {
        NativeCallbacks.onError = (_e, symbol) => resolve(symbol);
      });
      const handler = Handler.new$Looper(Looper.getMainLooper()!);
      handler.post(
        Runnable.implement(
          {
            run: () => {
              throw new Error('boom');
            },
          },
          { async: ['run'] },
        ),
      );
      expectEqual(
        await withTimeout(reported),
        'java.lang.Runnable#run()',
        'reported symbol',
      );
      NativeCallbacks.onError = undefined;
      const again = await withTimeout(
        new Promise<string>(resolve =>
          handler.post(
            Runnable.implement(
              { run: () => resolve('ok') },
              { async: ['run'] },
            ),
          ),
        ),
      );
      expectEqual(again, 'ok', 'looper still alive');
    },
  ],

  [
    'Java exceptions surface as NativeJavaError',
    () => {
      expectThrows(
        () => Intent.parseUri('#Intent;nope', 0),
        e =>
          isNativeJavaError(e) &&
          e.nativeClassName === 'java.net.URISyntaxException',
        'parseUri',
      );
    },
  ],

  [
    'Availability guard fails safely for APIs newer than the device',
    () => {
      AndroidApi.debugOverrideFullVersion = 2400000;
      try {
        expectThrows(
          () => Intent.new().removeLaunchSecurityProtection(),
          e => e instanceof NativeApiUnavailableError && e.required === '36',
          'guard',
        );
      } finally {
        AndroidApi.debugOverrideFullVersion = undefined;
      }
    },
  ],

  [
    'Lifecycle: 10k create/release, use-after-release, idempotent dispose',
    () => {
      for (let i = 0; i < 10000; i++) {
        Bundle.new().release();
      }
      for (let i = 0; i < 10000; i++) {
        Bundle.new(); // released by JS GC finalization
      }
      const b = Bundle.new();
      b.dispose();
      b.dispose();
      expectEqual(b.isReleased, true, 'isReleased');
      expectThrows(
        () => b.size(),
        e => String(e).includes('UseAfterReleaseError'),
        'use after release',
      );
      expectThrows(
        () => b.release(),
        e => String(e).includes('DoubleReleaseError'),
        'double release',
      );
    },
  ],
];

export async function selfTests(
  onResult: (r: TestResult) => void,
): Promise<void> {
  let pass = 0;
  let fail = 0;
  for (const [name, fn] of tests) {
    try {
      await fn();
      pass++;
      console.log(`NAB_TEST PASS ${name}`);
      onResult({ name, ok: true });
    } catch (e) {
      fail++;
      const msg = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
      console.log(`NAB_TEST FAIL ${name}: ${msg}`);
      onResult({ name, ok: false, error: msg });
    }
  }
  try {
    console.log(`NAB_TEST BENCH ${JSON.stringify(await benchmarks())}`);
  } catch (e) {
    console.log(`NAB_TEST BENCH failed: ${String(e)}`);
  }
  console.log(`NAB_TEST DONE pass=${pass} fail=${fail}`);
}
