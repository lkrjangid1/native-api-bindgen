// Minimal dart:ffi binding to libclang's stable C API (clang-c/Index.h).
// Only the functions native-api-bindgen needs. The library is loaded at run
// time from the locally installed Xcode toolchain; nothing is vendored.
// ignore_for_file: non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class CXString extends Struct {
  external Pointer<Void> data;
  @UnsignedInt()
  external int privateFlags;
}

final class CXCursor extends Struct {
  @UnsignedInt()
  external int kind;
  @Int()
  external int xdata;
  @Array(3)
  external Array<Pointer<Void>> data;
}

final class CXType extends Struct {
  @UnsignedInt()
  external int kind;
  @Array(2)
  external Array<Pointer<Void>> data;
}

final class CXSourceLocation extends Struct {
  @Array(2)
  external Array<Pointer<Void>> ptrData;
  @UnsignedInt()
  external int intData;
}

final class CXVersion extends Struct {
  @Int()
  external int major;
  @Int()
  external int minor;
  @Int()
  external int subminor;
}

final class CXPlatformAvailability extends Struct {
  external CXString platform;
  external CXVersion introduced;
  external CXVersion deprecated;
  external CXVersion obsoleted;
  @Int()
  external int unavailable;
  external CXString message;
}

/// Cursor kinds (clang-c/Index.h `CXCursorKind`).
abstract final class CursorKind {
  static const structDecl = 2;
  static const enumDecl = 5;
  static const fieldDecl = 6;
  static const enumConstantDecl = 7;
  static const functionDecl = 8;
  static const varDecl = 9;
  static const parmDecl = 10;
  static const objcInterfaceDecl = 11;
  static const objcCategoryDecl = 12;
  static const objcProtocolDecl = 13;
  static const objcPropertyDecl = 14;
  static const objcInstanceMethodDecl = 16;
  static const objcClassMethodDecl = 17;
  static const typedefDecl = 20;
  static const objcSuperClassRef = 40;
  static const objcProtocolRef = 41;
  static const objcClassRef = 42;
  static const typeRef = 43;
}

/// Type kinds (`CXTypeKind`).
abstract final class TypeKindC {
  static const unexposed = 1;
  static const void_ = 2;
  static const bool_ = 3;
  static const charU = 4;
  static const uchar = 5;
  static const char16 = 6;
  static const ushort = 8;
  static const uint = 9;
  static const ulong = 10;
  static const ulongLong = 11;
  static const charS = 13;
  static const schar = 14;
  static const short = 16;
  static const int_ = 17;
  static const long = 18;
  static const longLong = 19;
  static const float = 21;
  static const double_ = 22;
  static const longDouble = 23;
  static const objcId = 27;
  static const objcClass = 28;
  static const objcSel = 29;
  static const pointer = 101;
  static const blockPointer = 102;
  static const record = 105;
  static const enum_ = 106;
  static const typedef = 107;
  static const objcInterface = 108;
  static const objcObjectPointer = 109;
  static const functionProto = 111;
  static const constantArray = 112;
  static const elaborated = 119;
  static const objcObject = 161;
  static const objcTypeParam = 162;
  static const attributed = 163;
}

/// `CXTypeNullabilityKind`.
abstract final class NullabilityC {
  static const nonNull = 0;
  static const nullable = 1;
  static const unspecified = 2;
  static const invalid = 3;
}

/// `CXObjCPropertyAttrKind` bit flags.
abstract final class PropertyAttr {
  static const readonly = 1;
  static const getter = 2;
  static const readwrite = 8;
  static const copy = 32;
  static const setter = 128;
  static const weak = 512;
  static const class_ = 4096;
}

/// Native signature of the libclang cursor visitor.
typedef VisitorNative = UnsignedInt Function(CXCursor, CXCursor, Pointer<Void>);

/// Loaded libclang.
final class LibClang {
  LibClang(String path) : _lib = DynamicLibrary.open(path) {
    createIndex = _lib
        .lookupFunction<
          Pointer<Void> Function(Int, Int),
          Pointer<Void> Function(int, int)
        >('clang_createIndex');
    disposeIndex = _lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('clang_disposeIndex');
    parseTranslationUnit = _lib
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Char>,
            Pointer<Pointer<Char>>,
            Int,
            Pointer<Void>,
            UnsignedInt,
            UnsignedInt,
          ),
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Char>,
            Pointer<Pointer<Char>>,
            int,
            Pointer<Void>,
            int,
            int,
          )
        >('clang_parseTranslationUnit');
    disposeTranslationUnit = _lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('clang_disposeTranslationUnit');
    getTranslationUnitCursor = _lib
        .lookupFunction<
          CXCursor Function(Pointer<Void>),
          CXCursor Function(Pointer<Void>)
        >('clang_getTranslationUnitCursor');
    visitChildren = _lib
        .lookupFunction<
          UnsignedInt Function(
            CXCursor,
            Pointer<NativeFunction<VisitorNative>>,
            Pointer<Void>,
          ),
          int Function(
            CXCursor,
            Pointer<NativeFunction<VisitorNative>>,
            Pointer<Void>,
          )
        >('clang_visitChildren');
    getCursorKind = _lib
        .lookupFunction<UnsignedInt Function(CXCursor), int Function(CXCursor)>(
          'clang_getCursorKind',
        );
    getCursorSpelling = _lib
        .lookupFunction<
          CXString Function(CXCursor),
          CXString Function(CXCursor)
        >('clang_getCursorSpelling');
    getCursorType = _lib
        .lookupFunction<CXType Function(CXCursor), CXType Function(CXCursor)>(
          'clang_getCursorType',
        );
    getCursorResultType = _lib
        .lookupFunction<CXType Function(CXCursor), CXType Function(CXCursor)>(
          'clang_getCursorResultType',
        );
    getCursorDefinition = _lib
        .lookupFunction<
          CXCursor Function(CXCursor),
          CXCursor Function(CXCursor)
        >('clang_getCursorDefinition');
    equalCursors = _lib
        .lookupFunction<
          UnsignedInt Function(CXCursor, CXCursor),
          int Function(CXCursor, CXCursor)
        >('clang_equalCursors');
    cursorIsNull = _lib
        .lookupFunction<Int Function(CXCursor), int Function(CXCursor)>(
          'clang_Cursor_isNull',
        );
    getNumArguments = _lib
        .lookupFunction<Int Function(CXCursor), int Function(CXCursor)>(
          'clang_Cursor_getNumArguments',
        );
    getArgument = _lib
        .lookupFunction<
          CXCursor Function(CXCursor, UnsignedInt),
          CXCursor Function(CXCursor, int)
        >('clang_Cursor_getArgument');
    isObjCOptional = _lib
        .lookupFunction<UnsignedInt Function(CXCursor), int Function(CXCursor)>(
          'clang_Cursor_isObjCOptional',
        );
    isVariadic = _lib
        .lookupFunction<UnsignedInt Function(CXCursor), int Function(CXCursor)>(
          'clang_Cursor_isVariadic',
        );
    propertyAttributes = _lib
        .lookupFunction<
          UnsignedInt Function(CXCursor, UnsignedInt),
          int Function(CXCursor, int)
        >('clang_Cursor_getObjCPropertyAttributes');
    propertyGetterName = _lib
        .lookupFunction<
          CXString Function(CXCursor),
          CXString Function(CXCursor)
        >('clang_Cursor_getObjCPropertyGetterName');
    propertySetterName = _lib
        .lookupFunction<
          CXString Function(CXCursor),
          CXString Function(CXCursor)
        >('clang_Cursor_getObjCPropertySetterName');
    enumConstantValue = _lib
        .lookupFunction<LongLong Function(CXCursor), int Function(CXCursor)>(
          'clang_getEnumConstantDeclValue',
        );
    enumConstantUnsignedValue = _lib
        .lookupFunction<
          UnsignedLongLong Function(CXCursor),
          int Function(CXCursor)
        >('clang_getEnumConstantDeclUnsignedValue');
    enumIntegerType = _lib
        .lookupFunction<CXType Function(CXCursor), CXType Function(CXCursor)>(
          'clang_getEnumDeclIntegerType',
        );
    typedefUnderlying = _lib
        .lookupFunction<CXType Function(CXCursor), CXType Function(CXCursor)>(
          'clang_getTypedefDeclUnderlyingType',
        );
    getCursorLocation = _lib
        .lookupFunction<
          CXSourceLocation Function(CXCursor),
          CXSourceLocation Function(CXCursor)
        >('clang_getCursorLocation');
    getFileLocation = _lib
        .lookupFunction<
          Void Function(
            CXSourceLocation,
            Pointer<Pointer<Void>>,
            Pointer<UnsignedInt>,
            Pointer<UnsignedInt>,
            Pointer<UnsignedInt>,
          ),
          void Function(
            CXSourceLocation,
            Pointer<Pointer<Void>>,
            Pointer<UnsignedInt>,
            Pointer<UnsignedInt>,
            Pointer<UnsignedInt>,
          )
        >('clang_getFileLocation');
    getFileName = _lib
        .lookupFunction<
          CXString Function(Pointer<Void>),
          CXString Function(Pointer<Void>)
        >('clang_getFileName');
    platformAvailability = _lib
        .lookupFunction<
          Int Function(
            CXCursor,
            Pointer<Int>,
            Pointer<CXString>,
            Pointer<Int>,
            Pointer<CXString>,
            Pointer<CXPlatformAvailability>,
            Int,
          ),
          int Function(
            CXCursor,
            Pointer<Int>,
            Pointer<CXString>,
            Pointer<Int>,
            Pointer<CXString>,
            Pointer<CXPlatformAvailability>,
            int,
          )
        >('clang_getCursorPlatformAvailability');
    disposePlatformAvailability = _lib
        .lookupFunction<
          Void Function(Pointer<CXPlatformAvailability>),
          void Function(Pointer<CXPlatformAvailability>)
        >('clang_disposeCXPlatformAvailability');
    getTypeSpelling = _lib
        .lookupFunction<CXString Function(CXType), CXString Function(CXType)>(
          'clang_getTypeSpelling',
        );
    getCanonicalType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_getCanonicalType',
        );
    getPointeeType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_getPointeeType',
        );
    getModifiedType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_Type_getModifiedType',
        );
    getNamedType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_Type_getNamedType',
        );
    getTypeDeclaration = _lib
        .lookupFunction<CXCursor Function(CXType), CXCursor Function(CXType)>(
          'clang_getTypeDeclaration',
        );
    getTypedefName = _lib
        .lookupFunction<CXString Function(CXType), CXString Function(CXType)>(
          'clang_getTypedefName',
        );
    getNullability = _lib
        .lookupFunction<UnsignedInt Function(CXType), int Function(CXType)>(
          'clang_Type_getNullability',
        );
    objcBaseType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_Type_getObjCObjectBaseType',
        );
    numObjCTypeArgs = _lib
        .lookupFunction<UnsignedInt Function(CXType), int Function(CXType)>(
          'clang_Type_getNumObjCTypeArgs',
        );
    objcTypeArg = _lib
        .lookupFunction<
          CXType Function(CXType, UnsignedInt),
          CXType Function(CXType, int)
        >('clang_Type_getObjCTypeArg');
    numObjCProtocolRefs = _lib
        .lookupFunction<UnsignedInt Function(CXType), int Function(CXType)>(
          'clang_Type_getNumObjCProtocolRefs',
        );
    objcProtocolDecl = _lib
        .lookupFunction<
          CXCursor Function(CXType, UnsignedInt),
          CXCursor Function(CXType, int)
        >('clang_Type_getObjCProtocolDecl');
    getResultType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_getResultType',
        );
    getNumArgTypes = _lib
        .lookupFunction<Int Function(CXType), int Function(CXType)>(
          'clang_getNumArgTypes',
        );
    getArgType = _lib
        .lookupFunction<
          CXType Function(CXType, UnsignedInt),
          CXType Function(CXType, int)
        >('clang_getArgType');
    getArraySize = _lib
        .lookupFunction<LongLong Function(CXType), int Function(CXType)>(
          'clang_getArraySize',
        );
    getArrayElementType = _lib
        .lookupFunction<CXType Function(CXType), CXType Function(CXType)>(
          'clang_getArrayElementType',
        );
    getCString = _lib
        .lookupFunction<
          Pointer<Utf8> Function(CXString),
          Pointer<Utf8> Function(CXString)
        >('clang_getCString');
    disposeString = _lib
        .lookupFunction<Void Function(CXString), void Function(CXString)>(
          'clang_disposeString',
        );
    getNumDiagnostics = _lib
        .lookupFunction<
          UnsignedInt Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('clang_getNumDiagnostics');
    getDiagnostic = _lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, UnsignedInt),
          Pointer<Void> Function(Pointer<Void>, int)
        >('clang_getDiagnostic');
    getDiagnosticSeverity = _lib
        .lookupFunction<
          UnsignedInt Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('clang_getDiagnosticSeverity');
    getDiagnosticSpelling = _lib
        .lookupFunction<
          CXString Function(Pointer<Void>),
          CXString Function(Pointer<Void>)
        >('clang_getDiagnosticSpelling');
    disposeDiagnostic = _lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('clang_disposeDiagnostic');
    isBitField = _lib
        .lookupFunction<UnsignedInt Function(CXCursor), int Function(CXCursor)>(
          'clang_Cursor_isBitField',
        );
  }

  final DynamicLibrary _lib;

  late final Pointer<Void> Function(int, int) createIndex;
  late final void Function(Pointer<Void>) disposeIndex;
  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<Pointer<Char>>,
    int,
    Pointer<Void>,
    int,
    int,
  )
  parseTranslationUnit;
  late final void Function(Pointer<Void>) disposeTranslationUnit;
  late final CXCursor Function(Pointer<Void>) getTranslationUnitCursor;
  late final int Function(
    CXCursor,
    Pointer<NativeFunction<VisitorNative>>,
    Pointer<Void>,
  )
  visitChildren;
  late final int Function(CXCursor) getCursorKind;
  late final CXString Function(CXCursor) getCursorSpelling;
  late final CXType Function(CXCursor) getCursorType;
  late final CXType Function(CXCursor) getCursorResultType;
  late final CXCursor Function(CXCursor) getCursorDefinition;
  late final int Function(CXCursor, CXCursor) equalCursors;
  late final int Function(CXCursor) cursorIsNull;
  late final int Function(CXCursor) getNumArguments;
  late final CXCursor Function(CXCursor, int) getArgument;
  late final int Function(CXCursor) isObjCOptional;
  late final int Function(CXCursor) isVariadic;
  late final int Function(CXCursor) isBitField;
  late final int Function(CXCursor, int) propertyAttributes;
  late final CXString Function(CXCursor) propertyGetterName;
  late final CXString Function(CXCursor) propertySetterName;
  late final int Function(CXCursor) enumConstantValue;
  late final int Function(CXCursor) enumConstantUnsignedValue;
  late final CXType Function(CXCursor) enumIntegerType;
  late final CXType Function(CXCursor) typedefUnderlying;
  late final CXSourceLocation Function(CXCursor) getCursorLocation;
  late final void Function(
    CXSourceLocation,
    Pointer<Pointer<Void>>,
    Pointer<UnsignedInt>,
    Pointer<UnsignedInt>,
    Pointer<UnsignedInt>,
  )
  getFileLocation;
  late final CXString Function(Pointer<Void>) getFileName;
  late final int Function(
    CXCursor,
    Pointer<Int>,
    Pointer<CXString>,
    Pointer<Int>,
    Pointer<CXString>,
    Pointer<CXPlatformAvailability>,
    int,
  )
  platformAvailability;
  late final void Function(Pointer<CXPlatformAvailability>)
  disposePlatformAvailability;
  late final CXString Function(CXType) getTypeSpelling;
  late final CXType Function(CXType) getCanonicalType;
  late final CXType Function(CXType) getPointeeType;
  late final CXType Function(CXType) getModifiedType;
  late final CXType Function(CXType) getNamedType;
  late final CXCursor Function(CXType) getTypeDeclaration;
  late final CXString Function(CXType) getTypedefName;
  late final int Function(CXType) getNullability;
  late final CXType Function(CXType) objcBaseType;
  late final int Function(CXType) numObjCTypeArgs;
  late final CXType Function(CXType, int) objcTypeArg;
  late final int Function(CXType) numObjCProtocolRefs;
  late final CXCursor Function(CXType, int) objcProtocolDecl;
  late final CXType Function(CXType) getResultType;
  late final int Function(CXType) getNumArgTypes;
  late final CXType Function(CXType, int) getArgType;
  late final int Function(CXType) getArraySize;
  late final CXType Function(CXType) getArrayElementType;
  late final Pointer<Utf8> Function(CXString) getCString;
  late final void Function(CXString) disposeString;
  late final int Function(Pointer<Void>) getNumDiagnostics;
  late final Pointer<Void> Function(Pointer<Void>, int) getDiagnostic;
  late final int Function(Pointer<Void>) getDiagnosticSeverity;
  late final CXString Function(Pointer<Void>) getDiagnosticSpelling;
  late final void Function(Pointer<Void>) disposeDiagnostic;

  /// Converts and disposes a CXString.
  String str(CXString s) {
    final p = getCString(s);
    final out = p == nullptr ? '' : p.toDartString();
    disposeString(s);
    return out;
  }

  /// Children of [c], copied out of the visitor (safe to keep).
  List<CXCursor> children(CXCursor c) {
    _collected = [];
    visitChildren(c, _visitorPointer, nullptr);
    final out = _collected!;
    _collected = null;
    return out;
  }

  /// File path and byte offset of a cursor's location (its macro expansion
  /// site when inside a macro), or null for builtins.
  ({String file, int offset})? fileOffsetOf(CXCursor c) {
    final loc = getCursorLocation(c);
    final file = calloc<Pointer<Void>>();
    final offset = calloc<UnsignedInt>();
    try {
      getFileLocation(loc, file, nullptr, nullptr, offset);
      if (file.value == nullptr) return null;
      return (file: str(getFileName(file.value)), offset: offset.value);
    } finally {
      calloc.free(file);
      calloc.free(offset);
    }
  }

  /// File path of a cursor's location ('' for builtins).
  String fileOf(CXCursor c) {
    final loc = getCursorLocation(c);
    final file = calloc<Pointer<Void>>();
    try {
      getFileLocation(loc, file, nullptr, nullptr, nullptr);
      if (file.value == nullptr) return '';
      return str(getFileName(file.value));
    } finally {
      calloc.free(file);
    }
  }
}

List<CXCursor>? _collected;

int _visitor(CXCursor cursor, CXCursor parent, Pointer<Void> data) {
  // Copy the struct: the argument's storage is only valid during the call.
  final copy = calloc<CXCursor>();
  copy.ref.kind = cursor.kind;
  copy.ref.xdata = cursor.xdata;
  for (var i = 0; i < 3; i++) {
    copy.ref.data[i] = cursor.data[i];
  }
  _collected!.add(copy.ref);
  return 1; // CXChildVisit_Continue
}

final Pointer<NativeFunction<VisitorNative>> _visitorPointer =
    Pointer.fromFunction<VisitorNative>(_visitor, 0);
