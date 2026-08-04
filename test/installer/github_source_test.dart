import 'dart:convert';

import 'package:bentos_userland/installer.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The GitHub half, driven against a stubbed API: which release a stream means
/// in a repository that publishes several products, and what a missing token
/// says.
void main() {
  /// The campus as it really is: one repo, the userland's releases and a
  /// neighbour's, newest first — which is the order the API answers in.
  final releases = [
    {
      'tag_name': 'kernel-v0.4.0',
      'draft': false,
      'assets': [
        {'id': 90, 'name': 'bentos-release.json'},
      ],
    },
    {
      'tag_name': 'userland-v0.1.0',
      'draft': false,
      'assets': [
        {'id': 10, 'name': 'bentos-release.json'},
        {'id': 11, 'name': 'mem-linux-x64'},
      ],
    },
  ];

  final userlandManifest = {
    'product': 'bentos-userland',
    'version': '0.1.0',
    'executables': [
      {'name': 'mem', 'entrypoint': 'bin/mem.dart', 'platforms': ['linux-x64']},
    ],
    'artifacts': [
      {'name': 'mem', 'platform': 'linux-x64', 'asset': 'mem-linux-x64', 'sha256': 'ab' * 32},
    ],
  };

  const kernelManifest = {'product': 'bentos-kernel', 'version': '0.4.0', 'executables': [], 'artifacts': []};

  MockClient api({bool requireToken = true}) => MockClient((request) async {
        if (requireToken && !request.headers.containsKey('Authorization')) {
          return http.Response('{"message":"Not Found"}', 404);
        }
        final path = request.url.path;
        if (path.endsWith('/releases')) {
          return http.Response(json.encode(releases), 200);
        }
        if (path.endsWith('/releases/assets/10')) {
          return http.Response(json.encode(userlandManifest), 200);
        }
        if (path.endsWith('/releases/assets/90')) {
          return http.Response(json.encode(kernelManifest), 200);
        }
        return http.Response('{"message":"Not Found"}', 404);
      });

  GithubReleaseSource sourceFor(String prefix, {MockClient? client, Map<String, String>? env}) =>
      GithubReleaseSource(
        'bentos-userland',
        'cafe01/bentos-workspace',
        tagPrefix: prefix,
        client: client ?? api(),
        environment: env ?? const {'GH_TOKEN': 't'},
        // The clean machine the bootstrap lands on has no `gh` — the test says
        // so explicitly rather than inheriting this machine's login.
        keyringToken: () => null,
      );

  test('the stream is a tag prefix — a neighbour product\'s newer release is not it', () async {
    final manifest = await sourceFor('userland-v').manifest();
    expect(manifest.product, 'bentos-userland');
    expect(manifest.version, '0.1.0');
  });

  test('the same repo serves the neighbour under its own prefix', () async {
    final manifest = await sourceFor('kernel-v').manifest();
    expect(manifest.product, 'bentos-kernel');
  });

  test('a prefix nobody publishes under is named, not silently latest', () async {
    await expectLater(
      sourceFor('playground-v').manifest(),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('playground-v'))),
    );
  });

  test('a private repo with no token says so — the flip to public needs no code', () async {
    await expectLater(
      sourceFor('userland-v', env: const {}).manifest(),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('private'))),
    );
    // The very same call, unauthenticated, against a public repo: no token, no
    // 404, same code path.
    final public = await sourceFor(
      'userland-v',
      client: api(requireToken: false),
      env: const {},
    ).manifest();
    expect(public.version, '0.1.0');
  });
}
