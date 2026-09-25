import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/backend_project_probe.dart';

/// Health responses report reachability only. Exact project deletion requires
/// a separate, authorized Management lookup.
void main() {
  final project = Uri.parse('https://abcdefghijklmnopqrst.supabase.co');

  test('classifies health responses without proving deletion', () async {
    for (final (status, expected) in <(int, BackendProjectProbeResult)>[
      (200, BackendProjectProbeResult.exists),
      (401, BackendProjectProbeResult.accessDenied),
      (403, BackendProjectProbeResult.accessDenied),
      (404, BackendProjectProbeResult.missing),
      (429, BackendProjectProbeResult.indeterminate),
      (500, BackendProjectProbeResult.indeterminate),
      (503, BackendProjectProbeResult.indeterminate),
    ]) {
      final probe = BackendProjectProbe(client: _FakeHttpClient(status));
      expect(
        await probe.probe(project, publishableKey: 'sb_publishable_test'),
        expected,
        reason: 'HTTP $status',
      );
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
        await probe.probe(project, publishableKey: 'sb_publishable_test'),
        BackendProjectProbeResult.indeterminate,
        reason: error.toString(),
      );
    }
  });

  test('probes only the project health endpoint over https', () async {
    final client = _FakeHttpClient(200);
    final probe = BackendProjectProbe(client: client);

    await probe.probe(project, publishableKey: 'sb_publishable_test');
    expect(
      client.requested.single.toString(),
      project.replace(path: '/auth/v1/health').toString(),
    );
    expect(client.lastRequest?.apiKey, 'sb_publishable_test');

    expect(
      await probe.probe(
        Uri.parse('http://insecure.test'),
        publishableKey: 'sb_publishable_test',
      ),
      BackendProjectProbeResult.indeterminate,
    );
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.status, [this.error]);

  final int? status;
  final Object? error;
  final List<Uri> requested = <Uri>[];
  _FakeRequest? lastRequest;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    if (error != null) throw error!;
    return lastRequest = _FakeRequest(status!);
  }

  @override
  void close({bool force = false}) {}

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError('unused');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._status);

  final int _status;
  String? apiKey;

  @override
  HttpHeaders get headers => _FakeHeaders((name, value) {
    if (name == 'apikey') apiKey = value.toString();
  });

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_status);

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError('unused');
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this.onSet);

  final void Function(String, Object) onSet;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      onSet(name, value);

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
