/**
 * On-simulator self-tests for the generated React Native iOS bindings.
 * Each result is logged as `NAB_TEST PASS <name>` / `NAB_TEST FAIL <name>: <error>`,
 * followed by `NAB_TEST DONE pass=<n> fail=<n>` (read by tools/run_rn_ios_tests.sh).
 */
import {
  IosApi,
  NSArray,
  NSFileManager,
  NSOperationQueue,
  NSProcessInfo,
  NativeApiUnavailableError,
  UIColor,
  UIDevice,
  UIUserInterfaceIdiom,
  UIView,
  UIViewAutoresizing,
  UIViewController,
  isNativeObjCError,
  isNativeObjCException,
  nativeLog,
  type CGRect,
} from '../native-api-bindings/ios';
import { benchmarks } from './bench';
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

function rect(x: number, y: number, width: number, height: number): CGRect {
  return { origin: { x, y }, size: { width, height } };
}

const tests: Array<[string, () => void | Promise<void>]> = [
  [
    'UIDevice: strings and enum-typed property (main thread)',
    () => {
      const device = UIDevice.currentDevice;
      expectEqual(device.systemName, 'iOS', 'systemName');
      if (!device.model.includes('iPhone'))
        throw new Error(`model ${device.model}`);
      expectEqual(
        device.userInterfaceIdiom,
        UIUserInterfaceIdiom.UIUserInterfaceIdiomPhone,
        'idiom',
      );
    },
  ],

  [
    'NSProcessInfo: struct returned and passed by value',
    () => {
      const info = NSProcessInfo.processInfo;
      const v = info.operatingSystemVersion;
      if (v.majorVersion < 15n) throw new Error(`major ${v.majorVersion}`);
      expectEqual(
        UIDevice.currentDevice.systemVersion.startsWith(`${v.majorVersion}.`),
        true,
        'systemVersion',
      );
      expectEqual(
        info.isOperatingSystemAtLeastVersion(v),
        true,
        'atLeast(self)',
      );
      expectEqual(
        info.isOperatingSystemAtLeastVersion({
          majorVersion: v.majorVersion + 1n,
          minorVersion: 0n,
          patchVersion: 0n,
        }),
        false,
        'atLeast(next)',
      );
      if (info.processName.length === 0) throw new Error('processName');
    },
  ],

  [
    'UIView: nested CGRect through init and property',
    () => {
      const view = UIView.alloc().initWithFrame(rect(1, 2, 30, 40));
      const f = view.frame;
      expectEqual(
        `${f.origin.x},${f.origin.y},${f.size.width},${f.size.height}`,
        '1,2,30,40',
        'frame',
      );
      view.frame = rect(5, 6, 7, 8);
      expectEqual(view.frame.size.height, 8, 'frame setter');
    },
  ],

  [
    'UIView: NSInteger, BOOL (isHidden) and NS_OPTIONS properties',
    () => {
      const view = UIView.new$();
      view.tag = 42n;
      expectEqual(view.tag, 42n, 'tag');
      expectEqual(view.hidden, false, 'hidden');
      view.hidden = true;
      expectEqual(view.hidden, true, 'hidden (getter=isHidden)');
      const mask =
        UIViewAutoresizing.UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizing.UIViewAutoresizingFlexibleHeight;
      view.autoresizingMask = mask;
      expectEqual(view.autoresizingMask, mask, 'autoresizingMask');
    },
  ],

  [
    'view hierarchy: object arguments, nullable returns, NSArray',
    () => {
      const parent = UIView.new$();
      const child = UIView.new$();
      expectEqual(child.superview, null, 'no superview');
      parent.addSubview(child);
      expectEqual(parent.subviews.count, 1n, 'subviews.count');
      expectEqual(
        child.superview?.isSameObject(parent),
        true,
        'superview identity',
      );
      child.removeFromSuperview();
      expectEqual(child.superview, null, 'removed');
    },
  ],

  [
    'Objective-C blocks: sync comparator, main-queue and background callbacks',
    async () => {
      // NS_NOESCAPE block returning a value: runs synchronously on the JS
      // thread during the call.
      const parent = UIView.new$();
      for (const tag of [2n, 3n, 1n]) {
        const v = UIView.new$();
        v.tag = tag;
        parent.addSubview(v);
      }
      const sorted = parent.subviews.sortedArrayUsingComparator((a, b) => {
        const x = a!.as(UIView).tag;
        const y = b!.as(UIView).tag;
        return x < y ? -1n : x > y ? 1n : 0n;
      });
      expectEqual(
        [0n, 1n, 2n].map(i => sorted.objectAtIndex(i).as(UIView).tag).join(),
        '1,2,3',
        'sorted tags',
      );
      // Block invoked on the main thread (UIKit member): posted to JS.
      let ran = false;
      UIView.performWithoutAnimation(() => {
        ran = true;
      });
      const finished = await new Promise<boolean>(resolve =>
        UIView.animateWithDuration$animations$completion(
          0.01,
          () => {},
          f => resolve(f),
        ),
      );
      expectEqual(typeof finished, 'boolean', 'completion argument');
      expectEqual(ran, true, 'main-thread block delivered');
      // Escaping blocks on background threads: posted to JS.
      const queue = NSOperationQueue.new$();
      const done = new Set<number>();
      for (let i = 0; i < 5; i++) queue.addOperationWithBlock(() => done.add(i));
      queue.waitUntilAllOperationsAreFinished();
      for (let tries = 0; done.size < 5 && tries < 100; tries++) {
        await new Promise<void>(r => setTimeout(() => r(), 10));
      }
      expectEqual(done.size, 5, 'background blocks delivered');
    },
  ],

  [
    'nullable object property and class property',
    () => {
      const view = UIView.new$();
      expectEqual(view.backgroundColor, null, 'initial color');
      view.backgroundColor = UIColor.redColor;
      expectEqual(view.backgroundColor?.isEqual(UIColor.redColor), true, 'red');
      view.backgroundColor = null;
      expectEqual(view.backgroundColor, null, 'cleared');
    },
  ],

  [
    'UIViewController: lazy view, nullable NSString title, isA',
    () => {
      const vc = UIViewController.new$();
      expectEqual(vc.viewLoaded, false, 'viewLoaded before');
      const view = vc.view;
      expectEqual(vc.viewLoaded, true, 'viewLoaded after');
      expectEqual(UIView.isA(view), true, 'UIView.isA');
      expectEqual(UIDevice.isA(view), false, 'UIDevice.isA');
      expectEqual(vc.title, null, 'title');
      vc.title = 'Slice';
      expectEqual(vc.title, 'Slice', 'title roundtrip');
    },
  ],

  [
    'NSError ** throws NativeObjCError',
    () => {
      const fm = NSFileManager.defaultManager;
      expectThrows(
        () => fm.contentsOfDirectoryAtPath('/nab-does-not-exist'),
        e => isNativeObjCError(e) && e.domain === 'NSCocoaErrorDomain',
        'missing directory',
      );
      const root = fm.contentsOfDirectoryAtPath('/');
      if (root === null || root.count === 0n) throw new Error('listing /');
    },
  ],

  [
    'NSException becomes NativeObjCException',
    () => {
      const empty = UIView.new$().subviews;
      expectThrows(
        () => empty.objectAtIndex(3n),
        e => isNativeObjCException(e) && e.exceptionName === 'NSRangeException',
        'objectAtIndex out of range',
      );
      expectEqual(NSArray.isA(empty), true, 'NSArray.isA');
    },
  ],

  [
    'Promise variants: main queue (UIKit) and background queue (Foundation)',
    async () => {
      const view = UIView.alloc().initWithFrame(rect(0, 0, 10, 10));
      await view.layoutIfNeededAsync();
      expectEqual(
        await NSFileManager.defaultManager.fileExistsAtPathAsync('/'),
        true,
        'fileExists async',
      );
      let rejected = false;
      await NSFileManager.defaultManager
        .contentsOfDirectoryAtPathAsync('/nab-does-not-exist')
        .catch(e => {
          rejected = isNativeObjCError(e);
        });
      expectEqual(rejected, true, 'async NSError rejection');
    },
  ],

  [
    'availability guard: API newer than the OS throws',
    () => {
      if (IosApi.isAtLeast(27)) return; // guard not triggered on iOS 27+
      const vc = UIViewController.new$();
      expectThrows(
        () => vc.registerSceneAccessory(UIView.new$()),
        e => e instanceof NativeApiUnavailableError,
        'registerSceneAccessory on iOS < 27',
      );
    },
  ],

  [
    'lifecycle: release, use-after-release, 10k objects',
    () => {
      const v = UIView.new$();
      v.release();
      expectEqual(v.isReleased, true, 'isReleased');
      expectThrows(
        () => v.tag,
        e => String(e).includes('UseAfterReleaseError'),
        'use after release',
      );
      expectThrows(
        () => v.release(),
        e => String(e).includes('DoubleReleaseError'),
        'double release',
      );
      for (let i = 0; i < 10000; i++) {
        const o = NSProcessInfo.processInfo;
        o.release();
      }
    },
  ],
];

/** Logs a result line to the JS console and the unified log (release builds). */
function report(line: string): void {
  console.log(line);
  nativeLog(line);
}

export async function selfTests(
  onResult: (r: TestResult) => void,
): Promise<void> {
  let pass = 0;
  let fail = 0;
  for (const [name, fn] of tests) {
    try {
      await fn();
      pass++;
      report(`NAB_TEST PASS ${name}`);
      onResult({ name, ok: true });
    } catch (e) {
      fail++;
      const msg = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
      report(`NAB_TEST FAIL ${name}: ${msg}`);
      onResult({ name, ok: false, error: msg });
    }
  }
  try {
    report(`NAB_TEST BENCH ${JSON.stringify(await benchmarks())}`);
  } catch (e) {
    report(`NAB_TEST BENCH failed: ${String(e)}`);
  }
  report(`NAB_TEST DONE pass=${pass} fail=${fail}`);
}
