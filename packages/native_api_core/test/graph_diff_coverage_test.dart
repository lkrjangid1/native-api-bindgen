import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

const _prov = Provenance(
  platform: ApiPlatform.android,
  sourceKind: 'fixture',
  sdkVersion: '1',
);

ApiType _type(
  String id, {
  List<ApiMethod> methods = const [],
  TypeRef? superClass,
  Availability av = Availability.unknown,
}) => ApiType(
  id: id,
  name: id.split('.').last,
  kind: TypeKind.classType,
  namespace: id.substring(0, id.lastIndexOf('.')),
  provenance: _prov,
  superClass: superClass,
  methods: methods,
  availability: av,
);

ApiMethod _m(
  String owner,
  String name,
  TypeRef ret, {
  List<TypeRef> params = const [],
  ApiVisibility vis = ApiVisibility.public,
  SupportStatus support = SupportStatus.supported,
  List<Diagnostic> diags = const [],
}) => ApiMethod(
  id: SymbolIds.method(owner, name, params),
  name: name,
  kind: MethodKind.method,
  returnType: ret,
  parameters: [
    for (var i = 0; i < params.length; i++) ApiParameter('p$i', params[i]),
  ],
  visibility: vis,
  support: support,
  diagnostics: diags,
);

void main() {
  final intent = _type(
    'a.Intent',
    superClass: const DeclaredTypeRef('a.Object'),
    methods: [
      _m('a.Intent', 'getData', const DeclaredTypeRef('a.Uri')),
      _m(
        'a.Intent',
        'putExtras',
        const PrimitiveTypeRef(PrimitiveKind.void_),
        params: [const DeclaredTypeRef('a.Bundle')],
      ),
      _m(
        'a.Intent',
        'secret',
        const DeclaredTypeRef('a.Hidden'),
        vis: ApiVisibility.hiddenOrNonSdk,
        support: SupportStatus.unsupported,
        diags: [const Diagnostic(DiagnosticCode.nonSdkApi, 'hidden')],
      ),
    ],
  );
  final uri = _type(
    'a.Uri',
    methods: [_m('a.Uri', 'buildUpon', const DeclaredTypeRef('a.Builder'))],
  );
  final module = ApiModule(
    platform: ApiPlatform.android,
    sdkVersion: '1',
    generatorVersion: 'x',
    types: [intent, uri],
  );

  test('referenced types ignore non-generatable members', () {
    expect(referencedTypeIds(intent), {'a.Object', 'a.Uri', 'a.Bundle'});
  });

  test('closure respects depth and is deterministic', () {
    Iterable<String> n(String id) => module.typeById(id) == null
        ? const []
        : referencedTypeIds(module.typeById(id)!);
    expect(computeClosure(['a.Intent'], n, maxDepth: 0).keys, ['a.Intent']);
    expect(computeClosure(['a.Intent'], n, maxDepth: 1).keys, [
      'a.Bundle',
      'a.Intent',
      'a.Object',
      'a.Uri',
    ]);
    expect(computeClosure(['a.Intent'], n, maxDepth: 2)['a.Builder'], 2);
    expect(
      renderTree('a.Intent', n),
      'a.Intent\n ├─ a.Bundle\n ├─ a.Object\n └─ a.Uri',
    );
  });

  test('coverage counts exclusions by reason', () {
    final c = CoverageReport.of(module);
    expect(c.discovered['methods'], 4);
    expect(c.generated['methods'], 3);
    expect(c.excludedByReason, {'E006 NON_SDK_API': 1});
    expect(c.toText(), contains('E006 NON_SDK_API: 1'));
  });

  test('diff reports added/removed/changed/deprecated/availability', () {
    final newer = ApiModule(
      platform: ApiPlatform.android,
      sdkVersion: '2',
      generatorVersion: 'x',
      types: [
        _type(
          'a.Intent',
          superClass: const DeclaredTypeRef('a.Object'),
          av: const Availability(
            introduced: ApiVersion(1),
            deprecated: ApiVersion(2),
          ),
          methods: [
            _m('a.Intent', 'getData', const DeclaredTypeRef('a.Uri2')),
            _m(
              'a.Intent',
              'newMethod',
              const PrimitiveTypeRef(PrimitiveKind.void_),
            ),
          ],
        ),
      ],
    );
    final d = diffModules(module, newer);
    String kinds(String id) =>
        d.where((e) => e.symbolId == id).map((e) => e.kind.name).join(',');
    expect(kinds('a.Intent#newMethod()'), 'added');
    expect(kinds('a.Uri'), 'removed');
    expect(kinds('a.Intent'), 'deprecated,availabilityChanged');
    expect(kinds('a.Intent#getData()'), 'signatureChanged');
    expect(renderDiff(d), contains('ADDED\na.Intent#newMethod()'));
    expect(renderDiff(const []), 'No differences.');
  });
}
