import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What the installer does when the network is having a bad day — and, just as
/// much, what it refuses to do when the registry has simply answered.
///
/// The waits are injected, so the policy is proven without spending seven
/// seconds asleep, and every case counts the attempts: a retry that cannot be
/// counted is a claim about behaviour nobody observed.
void main() {
  final release = [
    {
      'tag_name': 'v0.1.0',
      'draft': false,
      'assets': [
        {'id': 10, 'name': 'bentos-release.json'},
      ],
    },
  ];

  const manifest = {
    'product': 'bentos-userland',
    'version': '0.1.0',
    'executables': <Object?>[],
    'artifacts': <Object?>[],
  };

  late List<Duration> slept;
  late int attempts;

  setUp(() {
    slept = [];
    attempts = 0;
  });

  /// A source over a client that fails [failures] times — by throwing, or by
  /// answering [status] — before serving the release normally.
  GithubReleaseSource sourceOver({
    required int failures,
    int? status,
    Object Function()? throwing,
  }) =>
      GithubReleaseSource(
        'bentos-userland',
        'cafe01/bentos-userland',
        tagPrefix: 'v',
        environment: const {'GH_TOKEN': 't'},
        keyringToken: () => null,
        sleep: (d) async => slept.add(d),
        client: MockClient((request) async {
          attempts++;
          if (attempts <= failures) {
            if (throwing != null) throw throwing();
            return http.Response('{"message":"upstream"}', status!);
          }
          return http.Response(
            json.encode(request.url.path.endsWith('/releases') ? release : manifest),
            200,
          );
        }),
      );

  test('a dropped connection is ridden out — three waits, doubling from a second', () async {
    // Two failures then success: the call comes back, and the schedule it slept
    // is the declared one rather than an accident of the loop.
    final source = sourceOver(failures: 2, throwing: () => http.ClientException('connection closed'));
    final read = await source.manifest();
    expect(read.version, '0.1.0');
    expect(slept, const [Duration(seconds: 1), Duration(seconds: 2)]);
  });

  test('a network that never comes back says so in one honest line', () async {
    final source = sourceOver(failures: 99, throwing: () => const SocketException('no route to host'));
    await expectLater(
      source.manifest(),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', allOf(
        contains('could not reach api.github.com'),
        contains('4 attempts'),
        contains('no route to host'),
        contains('run the same command again'),
      ))),
    );
    // Four tries in total — the first plus one per declared wait, and no more.
    expect(attempts, 4);
    expect(slept, GithubReleaseSource.backoff);
  });

  test('a server saying "not now" is retried: 429 and 5xx', () async {
    expect((await sourceOver(failures: 1, status: 429).manifest()).version, '0.1.0');
    expect(slept, const [Duration(seconds: 1)]);

    slept.clear();
    attempts = 0;
    expect((await sourceOver(failures: 2, status: 503).manifest()).version, '0.1.0');
    expect(slept, const [Duration(seconds: 1), Duration(seconds: 2)]);
  });

  /// The distinction the whole policy rests on: 401, 403 and 404 are the
  /// registry *answering* — who may have this, and whether it exists. Repeating
  /// them turns a clear no into a confused wait and tells the caller nothing new
  /// seven seconds later.
  for (final status in const [401, 403, 404]) {
    test('$status is an answer, not a stumble — asked once, never slept on', () async {
      await expectLater(sourceOver(failures: 99, status: status).manifest(), throwsA(isA<SourceException>()));
      expect(attempts, 1);
      expect(slept, isEmpty);
    });
  }

  test('a machine with no network gets a line, never a stack trace', () async {
    // The runner's own net, reached by a failure the source does not ride out:
    // a TLS handshake that fails is not worth repeating, and it must still leave
    // the terminal readable.
    final root = Directory.systemTemp.createTempSync('bentos-resilience-');
    addTearDown(() => root.deleteSync(recursive: true));

    final out = StringBuffer();
    final err = StringBuffer();
    final runner = BentosRunner(
      out: out,
      err: err,
      host: const HostPlatform('linux', 'x64'),
      environment: const {'GH_TOKEN': 't'},
      client: MockClient((_) async => throw const HandshakeException('certificate verify failed')),
      config: BentosConfig(
        home: p.join(root.path, 'home'),
        prefix: p.join(root.path, 'bin'),
        legacyPrefix: p.join(root.path, 'legacy-bin'),
        streams: BentosConfig.defaultStreams,
      ),
    );

    await runner.run(['install']);
    expect(runner.exitCode, 1);
    expect(err.toString(), startsWith('bentos: '));
    expect(err.toString(), contains('could not reach the network'));
    expect(err.toString(), contains('certificate verify failed'));
    // The dressing is the point: no exception class, no frames.
    expect(err.toString(), isNot(contains('HandshakeException')));
    expect(err.toString(), isNot(contains('#0')));
  });
}
