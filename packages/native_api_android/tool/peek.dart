import 'package:native_api_android/native_api_android.dart';

void main(List<String> a) {
  final p = AndroidSdkLocator().locate()!.select(a[0])!;
  final ex = openPlatform(p);
  final t = ex.loadType(a[1])!;
  for (final f in t.fields) {
    if (a.length < 3 || f.name.contains(a[2])) {
      print('${f.id} ${f.type} ${f.constantValue} ${f.availability}');
    }
  }
  for (final m in t.methods) {
    if (a.length < 3 || m.name.contains(a[2])) {
      print('${m.id} ${m.availability}');
    }
  }
}
