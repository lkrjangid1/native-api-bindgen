import 'package:native_api_ir/native_api_ir.dart';

/// JVM name of the continuation parameter of compiled `suspend` functions.
const kotlinContinuation = 'kotlin.coroutines.Continuation';

/// Whether [m] is a Kotlin `suspend` function.
bool isSuspend(ApiMethod m) => m.asyncKind == AsyncKind.suspend;

/// Parameters of a suspend function as written in Kotlin (without the
/// trailing continuation).
List<ApiParameter> suspendParameters(ApiMethod m) =>
    m.parameters.sublist(0, m.parameters.length - 1);

/// Result type of a suspend function: `T` from its `Continuation<? super T>`
/// parameter (`kotlin.Unit` for functions without a value, `Object` when the
/// signature is erased).
TypeRef suspendResult(ApiMethod m) {
  final c = m.parameters.last.type;
  if (c is DeclaredTypeRef && c.typeArguments.length == 1) {
    final a = c.typeArguments.single;
    if (a is WildcardTypeRef) {
      if (a.bound != null) return a.bound!;
    } else {
      return a;
    }
  }
  return const DeclaredTypeRef('java.lang.Object');
}

/// Whether [t] is `kotlin.Unit` (a suspend function without a value).
bool isKotlinUnit(TypeRef t) => t is DeclaredTypeRef && t.name == 'kotlin.Unit';
