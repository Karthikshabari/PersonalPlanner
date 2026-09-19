import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/backend_project_probe.dart';

/// A deleted project must be reported as missing only when the project host
/// itself answers 404; everything else must stay indeterminate so a network
/// problem can never invalidate a working (or merely unreachable) backend.
void main() {
  final project = Uri.parse('https://abcdefghijklmnopqrst.supabase.co');

  test('treats only an HTTP 404 as authoritative deletion', () async {
    for (final (status, expected) in <(int, BackendProjectProbeResult)>[
      (200, BackendProjectProbeResult.exists),
      (401, BackendProjectProbeResult.indeterminate),
      (404, BackendProjectProbeResult.missing),
      (429, BackendProjectProbeResult.indeterminate),
      (500, BackendProjectProbeResult.indeterminate),
      (503, BackendProjectProbeResult.indeterminate),
    ]) {
      final probe = BackendProjectProbe(client: _FakeHttpClient(status));
      expect(await probe.probe(project), expected, reason: 'HTTP $status');
    }
  });

  test('never treats a transport failure as deletion', () async {
    for (final error in <Object>[
      const SocketException('no such host'),
      TimeoutException('slow'),
      const HandshakeException('bad cert'),
      const HttpException('broken'),
    ]) {
      final probe = BackendProjectProbe(client: _FakeHttpClient(null, error));
      expect(
        await probe.probe(project),
        BackendProjectProbeResult.indeterminate,
        reason: error.toString(),
      );
    }
  });

  test('probes only the project health endpoint over https', () async {
    final client = _FakeHttpClient(200);
    final probe = BackendProjectProbe(client: client);

    await probe.probe(project);
    expect(client.requested.single.toString(), project.replace(
      path: '/auth/v1/health',
    ).toString());

    expect(
      await probe.probe(Uri.parse('http://insecure.test')),
      BackendProjectProbeResult.indeterminate,
    );
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.status, [this.error]);

  final int? status;
  final Object? error;
  final List<Uri> requested = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    if (error != null) throw error!;
    return _FakeRequest(status!);
  }

  @override
  void close({bool force = false}) {}

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError('unused');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._status);

  final int _status;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async =>
      _FakeResponse(_status);

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError('unused');
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode);

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError('unused');
}
