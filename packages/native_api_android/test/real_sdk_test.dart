@Tags(['sdk'])
library;

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

/// Runs against the locally installed Android SDK (platform 36 if present,
/// otherwise the highest stable). Skips with a reason when no SDK exists.
void main() {
  final sdk = AndroidSdkLocator().locate();
  final platform = sdk?.select('36') ?? sdk?.select('auto');
  if (platform == null) {
    test('real SDK', () {}, skip: 'No Android SDK platform installed');
    return;
  }
  late ApiModule m;
  setUpAll(() {
    m = openPlatform(platform)
        .extract(
          const ExtractionRequest(
            entries: [
              'android.content.Intent',
              'android.net.Uri',
              'android.os.Bundle',
              'android.os.Handler',
              'android.os.Looper',
              'android.app.Activity',
            ],
            depth: 0,
          ),
        )
        .module;
  });

  test('slice classes and inheritance chain are present', () {
    for (final id in [
      'android.content.Intent',
      'android.net.Uri',
      'android.os.Bundle',
      'android.os.BaseBundle',
      'android.os.Handler',
      'android.os.Looper',
      'android.app.Activity',
      'android.view.ContextThemeWrapper',
      'android.content.ContextWrapper',
      'android.content.Context',
      'java.lang.Object',
    ]) {
      expect(m.typeById(id), isNotNull, reason: id);
    }
    expect(
      m.typeById('android.app.Activity')!.superClass!.erasedId,
      'android.view.ContextThemeWrapper',
    );
  });

  test('signatures match the SDK', () {
    final setData =
        m.nodeById('android.content.Intent#setData(android.net.Uri)')!
            as ApiMethod;
    expect(
      setData.nativeDescriptor,
      '(Landroid/net/Uri;)Landroid/content/Intent;',
    );
    expect(setData.parameters.single.type.nullability, Nullability.nullable);
    expect(setData.returnType.nullability, Nullability.nonnull);
    expect(setData.availability.introduced, const ApiVersion(1));
    final parse =
        m.nodeById('android.net.Uri#parse(java.lang.String)')! as ApiMethod;
    expect(parse.isStatic, isTrue);
    final post =
        m.nodeById('android.os.Handler#post(java.lang.Runnable)')! as ApiMethod;
    expect(post.returnType, const PrimitiveTypeRef(PrimitiveKind.boolean));
    final action =
        m.nodeById('android.content.Intent#ACTION_VIEW')! as ApiField;
    expect(action.constantValue!.literal, 'android.intent.action.VIEW');
    final getMain =
        m.nodeById('android.os.Looper#getMainLooper()')! as ApiMethod;
    expect(getMain.isStatic, isTrue);
  });

  test('no slice member is misclassified as non-SDK', () {
    for (final t in m.types) {
      for (final n in [t, ...t.methods, ...t.fields]) {
        expect(n.visibility, ApiVisibility.public, reason: n.id);
      }
    }
  });
}
