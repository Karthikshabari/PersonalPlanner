import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

const _transactionId = '0123456789abcdef0123456789abcdef';
const _capability = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD';
const _projectRef = 'abcdefghijklmnopqrst';
const _publishableKey = 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu';

class _FakeTransport implements ProvisioningTransport {
  _FakeTransport(this.handler);

  final Future<ProvisioningHttpResponse> Function(
    ProvisioningHttpRequest request,
  )
  handler;
  final List<ProvisioningHttpRequest> requests = <ProvisioningHttpRequest>[];

  @override
  Future<ProvisioningHttpResponse> send(ProvisioningHttpRequest request) {
    requests.add(request);
    return handler(request);
  }
}

ProvisioningHttpResponse _json(Map<String, dynamic> body, {int status = 200}) =>
    ProvisioningHttpResponse(statusCode: status, body: jsonEncode(body));

Map<String, dynamic> _snapshot(
  String state, {
  String? projectRef,
  String? error,
  Map<String, dynamic>? runtimeConfig,
}) => <String, dynamic>{
  'schema': 2,
  'state': state,
  'createdAt': 1,
  'updatedAt': 2,
  'expiresAt': 3600000,
  'createAttempts': 0,
  'expensiveAttempts': 0,
  'projectRef': ?projectRef,
  'error': ?error,
  'runtimeConfig': ?runtimeConfig,
};

Map<String, dynamic> _runtimeConfig() => <String, dynamic>{
  'projectRef': _projectRef,
  'projectUrl': 'https://$_projectRef.supabase.co',
  'publishableKey': _publishableKey,
};

ProvisioningClient _client(_FakeTransport transport) => ProvisioningClient(
  baseUrl: Uri.parse('https://worker.test'),
  transport: transport,
);

Matcher _protocolError() => throwsA(
  isA<ProvisioningApiException>().having(
    (error) => error.kind,
    'kind',
    ProvisioningErrorKind.protocol,
  ),
);

void main() {
  group('Management account project resolution', () {
    test(
      'local READY recovery parses verified alternative candidates',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(<String, dynamic>{
            'projectExists': null,
            'projectStatus': 'legacy_candidates',
            'candidates': <Map<String, dynamic>>[
              <String, dynamic>{
                'projectRef': _projectRef,
                'name': 'Recovered cloud',
              },
            ],
          }),
        );
        final result = await _client(transport).checkProject(
          _projectRef,
          transactionId: _transactionId,
          capability: _capability,
        );
        expect(result.existence, ProjectExistence.candidateRecovery);
        expect(result.candidates.single.projectRef, _projectRef);
      },
    );

    test(
      'parses verified legacy candidates without guessing from a name',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(<String, dynamic>{
            'kind': 'candidates',
            'candidates': <Map<String, dynamic>>[
              <String, dynamic>{
                'projectRef': _projectRef,
                'name': 'Renamed cloud',
                'region': 'ap-south-1',
              },
            ],
          }),
        );
        final result = await _client(transport)
            .resolve(_transactionId, capability: _capability);
        expect(result.snapshot, isNull);
        expect(result.candidates.single.projectRef, _projectRef);
        expect(result.candidates.single.name, 'Renamed cloud');
        expect(
          transport.requests.single.uri.path,
          '/v1/provisioning/transactions/$_transactionId/resolve',
        );
      },
    );

    test('parses an exact mapped READY project on a second device', () async {
      final transport = _FakeTransport(
        (_) async => _json(
          _snapshot(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: _runtimeConfig(),
          ),
        ),
      );
      final result = await _client(transport)
          .resolve(_transactionId, capability: _capability);
      expect(result.snapshot?.runtimeConfig?.projectRef, _projectRef);
      expect(result.candidates, isEmpty);
    });

    test('adoption sends only the exact chosen ref', () async {
      final transport = _FakeTransport(
        (_) async => _json(
          _snapshot(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: _runtimeConfig(),
          ),
        ),
      );
      final result = await _client(
        transport,
      ).adopt(_transactionId, capability: _capability, projectRef: _projectRef);
      expect(result.projectRef, _projectRef);
      expect(jsonDecode(transport.requests.single.body!), <String, dynamic>{
        'projectRef': _projectRef,
      });
    });

    test(
      'discovery 502 is retryable and cannot become an empty list',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(<String, dynamic>{
            'error': 'candidate_discovery_failed',
          }, status: 502),
        );
        await expectLater(
          _client(transport).resolve(_transactionId, capability: _capability),
          throwsA(
            isA<ProvisioningApiException>().having(
              (error) => error.failureClass,
              'failureClass',
              ProvisioningFailureClass.retryable,
            ),
          ),
        );
      },
    );
  });

  group('transaction creation', () {
    test('posts an empty body and returns the provisioning grant', () async {
      final transport = _FakeTransport(
        (_) async => _json(<String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl':
              'https://api.supabase.com/v1/oauth/authorize?client_id=x',
          'expiresIn': 3600,
        }),
      );

      final grant = await _client(transport).createTransaction();

      expect(grant.transactionId, _transactionId);
      expect(grant.capability, _capability);
      expect(grant.expiresIn, const Duration(hours: 1));
      expect(grant.authorizationUrl.host, 'api.supabase.com');

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://worker.test/v1/provisioning/transactions',
      );
      expect(request.body, '{}');
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    test('rejects an unusable transaction id or capability', () async {
      for (final body in <Map<String, dynamic>>[
        <String, dynamic>{
          'transactionId': 'ABCDEF0123456789abcdef0123456789',
          'accessToken': _capability,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 3600,
        },
        <String, dynamic>{
          'transactionId': 'short',
          'accessToken': _capability,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 3600,
        },
        <String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': 'too-short',
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 3600,
        },
        <String, dynamic>{
          'transactionId': _transactionId,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 3600,
        },
      ]) {
        await expectLater(
          _client(_FakeTransport((_) async => _json(body))).createTransaction(),
          _protocolError(),
        );
      }
    });

    test('rejects an unusable authorization URL or expiry', () async {
      for (final body in <Map<String, dynamic>>[
        <String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl': '/v1/oauth/authorize',
          'expiresIn': 3600,
        },
        <String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl': 'http://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 3600,
        },
        <String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 0,
        },
        <String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 999999,
        },
        <String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': '3600',
        },
      ]) {
        await expectLater(
          _client(_FakeTransport((_) async => _json(body))).createTransaction(),
          _protocolError(),
        );
      }
    });
  });

  group('errors', () {
    test('maps a sanitized worker error without echoing the body', () async {
      final transport = _FakeTransport(
        (_) async => ProvisioningHttpResponse(
          statusCode: 502,
          body: jsonEncode(<String, dynamic>{
            'error': 'project_creation_failed',
            'details': 'sb_secret_abcdefghijklmnopqrstuvwxyz',
          }),
        ),
      );

      try {
        await _client(transport).createTransaction();
        fail('expected a provisioning failure');
      } on ProvisioningApiException catch (error) {
        expect(error.kind, ProvisioningErrorKind.worker);
        expect(error.code, 'project_creation_failed');
        expect(error.statusCode, 502);
        expect(error.failureClass, ProvisioningFailureClass.retryable);
        expect(error.toString(), isNot(contains('sb_secret_')));
      }
    });

    test('treats an HTML 502 as retryable without showing its body', () async {
      final transport = _FakeTransport(
        (_) async => const ProvisioningHttpResponse(
          statusCode: 502,
          body: '<html>gateway error</html>',
        ),
      );

      await expectLater(
        _client(transport).createTransaction(),
        throwsA(
          isA<ProvisioningApiException>()
              .having(
                (error) => error.kind,
                'kind',
                ProvisioningErrorKind.worker,
              )
              .having((error) => error.statusCode, 'statusCode', 502)
              .having(
                (error) => error.failureClass,
                'failureClass',
                ProvisioningFailureClass.retryable,
              )
              .having(
                (error) => error.message.contains('<html>'),
                'body hidden',
                isFalse,
              ),
        ),
      );
    });

    test('still rejects a malformed client-error response', () async {
      final transport = _FakeTransport(
        (_) async => const ProvisioningHttpResponse(
          statusCode: 400,
          body: '<html>unexpected</html>',
        ),
      );
      await expectLater(
        _client(transport).createTransaction(),
        throwsA(
          isA<ProvisioningApiException>().having(
            (error) => error.failureClass,
            'failureClass',
            ProvisioningFailureClass.protocol,
          ),
        ),
      );
    });

    test('propagates transport failures as retryable typed errors', () async {
      final transport = _FakeTransport(
        (_) async => throw const ProvisioningApiException(
          ProvisioningErrorKind.network,
          'The provisioning service could not be reached.',
        ),
      );

      await expectLater(
        _client(transport).createTransaction(),
        throwsA(
          isA<ProvisioningApiException>()
              .having(
                (error) => error.failureClass,
                'failureClass',
                ProvisioningFailureClass.retryable,
              )
              .having(
                (error) => error.kind,
                'kind',
                ProvisioningErrorKind.network,
              ),
        ),
      );
    });

    test(
      'the default transport turns an unreachable host into a retryable error',
      () async {
        final client = ProvisioningClient(
          baseUrl: Uri.parse('https://127.0.0.1:1'),
          transport: IoProvisioningTransport(
            timeout: const Duration(seconds: 5),
          ),
        );

        await expectLater(
          client.createTransaction(),
          throwsA(
            isA<ProvisioningApiException>().having(
              (error) => error.failureClass,
              'failureClass',
              ProvisioningFailureClass.retryable,
            ),
          ),
        );
      },
    );

    test('classifies every production error code', () async {
      const expected = <String, ProvisioningFailureClass>{
        'oauth_expired': ProvisioningFailureClass.restartRequired,
        'oauth_state_invalid': ProvisioningFailureClass.restartRequired,
        'provisioning_expired': ProvisioningFailureClass.restartRequired,
        'organization_not_found': ProvisioningFailureClass.actionRequired,
        'organization_discovery_failed': ProvisioningFailureClass.retryable,
        'project_creation_failed': ProvisioningFailureClass.retryable,
        'migration_failed': ProvisioningFailureClass.retryable,
        'verification_indeterminate': ProvisioningFailureClass.retryable,
        'runtime_config_unavailable': ProvisioningFailureClass.retryable,
        'operation_in_progress': ProvisioningFailureClass.retryable,
        'rate_limited': ProvisioningFailureClass.retryable,
        'temporarily_unavailable': ProvisioningFailureClass.retryable,
        'project_identity_ambiguous': ProvisioningFailureClass.terminal,
        'migration_history_mismatch': ProvisioningFailureClass.terminal,
        'verification_failed': ProvisioningFailureClass.terminal,
        'invalid_request': ProvisioningFailureClass.protocol,
      };

      for (final entry in expected.entries) {
        expect(
          classifyProvisioningErrorCode(entry.key, 400),
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        classifyProvisioningErrorCode('something_new', 503),
        ProvisioningFailureClass.retryable,
      );
      expect(
        classifyProvisioningErrorCode('something_new', 429),
        ProvisioningFailureClass.retryable,
      );
      expect(
        classifyProvisioningErrorCode('something_new', 410),
        ProvisioningFailureClass.restartRequired,
      );
      expect(
        classifyProvisioningErrorCode('something_new', 400),
        ProvisioningFailureClass.protocol,
      );
    });
  });

  group('authenticated requests', () {
    final operations = <String, ({String method, String path, String body})>{
      'snapshot': (
        method: 'GET',
        path: '/v1/provisioning/transactions/$_transactionId',
        body: '',
      ),
      'organizations': (
        method: 'GET',
        path: '/v1/provisioning/transactions/$_transactionId/organizations',
        body: '',
      ),
      'selectOrganization': (
        method: 'POST',
        path: '/v1/provisioning/transactions/$_transactionId/organization',
        body: '{"slug":"owner-org","projectName":"personal-planner-safe","idempotencyKey":"test-idempotency-key"}',
      ),
      'create': (
        method: 'POST',
        path: '/v1/provisioning/transactions/$_transactionId/create',
        body: '{}',
      ),
      'reconcile': (
        method: 'POST',
        path: '/v1/provisioning/transactions/$_transactionId/reconcile',
        body: '{}',
      ),
      'migrate': (
        method: 'POST',
        path: '/v1/provisioning/transactions/$_transactionId/migrate',
        body: '{}',
      ),
      'verify': (
        method: 'POST',
        path: '/v1/provisioning/transactions/$_transactionId/verify',
        body: '{}',
      ),
    };

    test('use the documented method, path and body', () async {
      for (final entry in operations.entries) {
        final transport = _FakeTransport(
          (_) async => entry.key == 'organizations'
              ? _json(<String, dynamic>{'organizations': <dynamic>[]})
              : _json(_snapshot('authorization_pending')),
        );
        final client = _client(transport);

        switch (entry.key) {
          case 'snapshot':
            await client.snapshot(_transactionId, capability: _capability);
          case 'organizations':
            await client.organizations(_transactionId, capability: _capability);
          case 'selectOrganization':
            await client.selectOrganization(
              _transactionId,
              capability: _capability,
              slug: 'owner-org',
              projectName: 'personal-planner-safe',
              idempotencyKey: 'test-idempotency-key',
            );
          case 'create':
            await client.create(_transactionId, capability: _capability);
          case 'reconcile':
            await client.reconcile(_transactionId, capability: _capability);
          case 'migrate':
            await client.migrate(_transactionId, capability: _capability);
          case 'verify':
            await client.verify(_transactionId, capability: _capability);
        }

        final request = transport.requests.single;
        expect(request.method, entry.value.method, reason: entry.key);
        expect(
          request.uri.toString(),
          'https://worker.test${entry.value.path}',
          reason: entry.key,
        );
        expect(
          request.headers['authorization'],
          'Provisioning $_capability',
          reason: entry.key,
        );
        if (entry.value.method == 'POST') {
          expect(request.body, entry.value.body, reason: entry.key);
        } else {
          expect(request.body, isNull, reason: entry.key);
        }
        expect(request.uri.query, isEmpty, reason: entry.key);
      }
    });

    test('reject a transaction id this client cannot address', () async {
      final transport = _FakeTransport(
        (_) async => _json(_snapshot('authorization_pending')),
      );

      await expectLater(
        _client(transport)
            .snapshot('not-a-transaction', capability: _capability),
        _protocolError(),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('snapshot parsing', () {
    test(
      'reports a claimed failed callback without leaking OAuth state',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(<String, dynamic>{
            ..._snapshot('authorization_pending'),
            'authorizationCompleted': false,
            'authorizationFailed': true,
          }),
        );
        final snapshot = await _client(transport)
            .snapshot(_transactionId, capability: _capability);
        expect(snapshot.authorizationFailed, isTrue);
        expect(snapshot.authorizationCompleted, isFalse);
      },
    );

    test('retries authorization on the exact existing transaction', () async {
      final transport = _FakeTransport(
        (_) async => _json(<String, dynamic>{
          'authorizationUrl':
              'https://api.supabase.com/v1/oauth/authorize?state=fresh',
        }),
      );
      final url = await _client(
        transport,
      ).retryProvisioningAuthorization(_transactionId, capability: _capability);
      expect(url.queryParameters['state'], 'fresh');
      expect(transport.requests.single.method, 'POST');
      expect(
        transport.requests.single.uri.path,
        '/v1/provisioning/transactions/$_transactionId/authorization/retry',
      );
      expect(
        transport.requests.single.headers['authorization'],
        'Provisioning $_capability',
      );
    });

    test(
      'accepts only a ready snapshot with a valid runtime configuration',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(
            _snapshot(
              'ready',
              projectRef: _projectRef,
              runtimeConfig: _runtimeConfig(),
            ),
          ),
        );

        final snapshot = await _client(transport)
            .snapshot(_transactionId, capability: _capability);

        expect(snapshot.state, ProvisioningState.ready);
        expect(snapshot.isReady, isTrue);
        expect(snapshot.projectRef, _projectRef);
        expect(snapshot.runtimeConfig?.publishableKey, _publishableKey);
        expect(
          snapshot.runtimeConfig?.projectUrl,
          'https://$_projectRef.supabase.co',
        );
      },
    );

    test('rejects a ready snapshot without a runtime configuration', () async {
      final transport = _FakeTransport(
        (_) async => _json(_snapshot('ready', projectRef: _projectRef)),
      );

      await expectLater(
        _client(transport).snapshot(_transactionId, capability: _capability),
        _protocolError(),
      );
    });

    test('rejects a runtime configuration before ready', () async {
      final transport = _FakeTransport(
        (_) async =>
            _json(_snapshot('verifying', runtimeConfig: _runtimeConfig())),
      );

      await expectLater(
        _client(transport).snapshot(_transactionId, capability: _capability),
        _protocolError(),
      );
    });

    test('rejects unknown, local-only, and malformed snapshots', () async {
      final bodies = <Map<String, dynamic>>[
        _snapshot('backend_resolving'),
        _snapshot('local_only'),
        <String, dynamic>{'schema': 2},
        _snapshot('verifying', projectRef: 'ABCDEFGHIJKLMNOPQRST'),
        <String, dynamic>{'projectRef': _projectRef},
        <String, dynamic>{},
      ];

      for (final body in bodies) {
        await expectLater(
          _client(_FakeTransport((_) async => _json(body)))
              .snapshot(_transactionId, capability: _capability),
          _protocolError(),
          reason: jsonEncode(body),
        );
      }
    });

    test('rejects responses that are not JSON objects', () async {
      for (final body in <String>['', 'not json', '[]', '"state"']) {
        await expectLater(
          _client(
            _FakeTransport(
              (_) async =>
                  ProvisioningHttpResponse(statusCode: 200, body: body),
            ),
          ).snapshot(_transactionId, capability: _capability),
          _protocolError(),
          reason: body,
        );
      }
    });

    test('parses optional snapshot metadata', () async {
      final transport = _FakeTransport(
        (_) async => _json(<String, dynamic>{
          ..._snapshot('organization_selected', projectRef: _projectRef),
          'organizationSlug': 'owner-org',
          'requestedProjectName': 'personal-planner-safe',
          'error': 'project_creation_failed',
        }),
      );

      final snapshot = await _client(transport)
          .snapshot(_transactionId, capability: _capability);

      expect(snapshot.organizationSlug, 'owner-org');
      expect(snapshot.requestedProjectName, 'personal-planner-safe');
      expect(snapshot.errorCode, 'project_creation_failed');
      expect(snapshot.expiresAt, isNotNull);
    });
  });

  group('organization discovery', () {
    test(
      'returns typed organization summaries, including an empty list',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(<String, dynamic>{
            'organizations': <dynamic>[
              <String, dynamic>{
                'id': 'org-1',
                'name': 'Owner Org',
                'slug': 'owner-org',
              },
            ],
          }),
        );

        final organizations = await _client(transport)
            .organizations(_transactionId, capability: _capability);

        expect(organizations, hasLength(1));
        expect(organizations.single.slug, 'owner-org');
        expect(organizations.single.name, 'Owner Org');

        final empty = await _client(
          _FakeTransport(
            (_) async => _json(<String, dynamic>{'organizations': <dynamic>[]}),
          ),
        ).organizations(_transactionId, capability: _capability);
        expect(empty, isEmpty);
      },
    );

    test('rejects a malformed or oversized organization list', () async {
      final bodies = <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{'organizations': 'owner-org'},
        <String, dynamic>{
          'organizations': <dynamic>[
            <String, dynamic>{'id': 'org-1', 'name': 'Owner'},
          ],
        },
        <String, dynamic>{
          'organizations': <dynamic>[
            <String, dynamic>{'id': 'org-1', 'name': 'Owner', 'slug': 7},
          ],
        },
        <String, dynamic>{
          'organizations': List<dynamic>.generate(
            101,
            (index) => <String, dynamic>{
              'id': 'org-$index',
              'name': 'Org',
              'slug': 'org-$index',
            },
          ),
        },
      ];

      for (final body in bodies) {
        await expectLater(
          _client(_FakeTransport((_) async => _json(body)))
              .organizations(_transactionId, capability: _capability),
          _protocolError(),
          reason: jsonEncode(body),
        );
      }
    });

    test('maps a worker error to a typed failure', () async {
      final transport = _FakeTransport(
        (_) async => _json(<String, dynamic>{
          'error': 'organization_discovery_failed',
        }, status: 502),
      );

      await expectLater(
        _client(transport)
            .organizations(_transactionId, capability: _capability),
        throwsA(
          isA<ProvisioningApiException>()
              .having(
                (error) => error.code,
                'code',
                'organization_discovery_failed',
              )
              .having(
                (error) => error.failureClass,
                'failureClass',
                ProvisioningFailureClass.retryable,
              ),
        ),
      );
    });
  });

  group('configuration and diagnostics', () {
    test(
      'uses the public production base URL when no override is supplied',
      () async {
        final transport = _FakeTransport(
          (_) async => _json(<String, dynamic>{
            'transactionId': _transactionId,
            'accessToken': _capability,
            'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
            'expiresIn': 3600,
          }),
        );

        await ProvisioningClient.fromConfig(transport: transport)
            .createTransaction();

        expect(
          transport.requests.single.uri,
          Uri.parse(
            'https://your-worker.example.workers.dev/v1/provisioning/transactions',
          ),
        );
      },
    );

    test('rejects a base URL that is not https', () {
      expect(
        () => ProvisioningClient(
          baseUrl: Uri.parse('http://worker.test'),
          transport: _FakeTransport((_) async => _json(<String, dynamic>{})),
        ),
        throwsArgumentError,
      );
    });

    test('never exposes the capability through diagnostics', () async {
      final transport = _FakeTransport(
        (_) async => _json(<String, dynamic>{
          'transactionId': _transactionId,
          'accessToken': _capability,
          'authorizationUrl': 'https://api.supabase.com/v1/oauth/authorize',
          'expiresIn': 3600,
        }),
      );

      final grant = await _client(transport).createTransaction();
      final snapshot = await _client(
        _FakeTransport(
          (_) async => _json(
            _snapshot(
              'ready',
              projectRef: _projectRef,
              runtimeConfig: _runtimeConfig(),
            ),
          ),
        ),
      ).snapshot(_transactionId, capability: _capability);

      expect(grant.toString(), isNot(contains(_capability)));
      expect(snapshot.toString(), isNot(contains(_publishableKey)));
      expect(
        snapshot.runtimeConfig.toString(),
        isNot(contains(_publishableKey)),
      );
      expect(
        const ProvisioningApiException(
          ProvisioningErrorKind.worker,
          'Provisioning stopped: operation_in_progress (HTTP 409).',
        ).toString(),
        isNot(contains(_capability)),
      );
    });

    test('reads the Management authorization status', () async {
      final transport = _FakeTransport(
        (_) async => _json(<String, dynamic>{
          'authorized': true,
          'pending': false,
          'revokedAt': null,
          'authorizationExpiresAt': 1_800_000_000_000,
          'releaseUnconfirmed': false,
          'emailConfirmationRedirect': 'https://worker.test/auth/confirmed',
        }),
      );

      final status = await _client(transport)
          .managementAuthorization(_transactionId, capability: _capability);

      expect(status.authorized, isTrue);
      expect(status.pending, isFalse);
      expect(status.revokedAt, isNull);
      expect(
        status.authorizationExpiresAt,
        DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000, isUtc: true),
      );
      expect(
        status.emailConfirmationRedirect,
        'https://worker.test/auth/confirmed',
      );
      expect(
        transport.requests.single.uri.path,
        '/v1/provisioning/transactions/$_transactionId/authorization',
      );
      expect(
        transport.requests.single.headers['authorization'],
        'Provisioning $_capability',
      );
    });

    test('requires a https Management authorization URL', () async {
      final request = await _client(
        _FakeTransport(
          (_) async => _json(<String, dynamic>{
            'authorizationUrl':
                'https://api.supabase.com/v1/oauth/authorize?state=x',
            'expiresIn': 2592000,
          }),
        ),
      ).startManagementAuthorization(_transactionId, capability: _capability);

      expect(request.authorizationUrl.host, 'api.supabase.com');
      expect(request.expiresIn, const Duration(days: 30));

      await expectLater(
        _client(
          _FakeTransport(
            (_) async => _json(<String, dynamic>{
              'authorizationUrl': 'http://api.supabase.com/v1/oauth/authorize',
              'expiresIn': 60,
            }),
          ),
        ).startManagementAuthorization(_transactionId, capability: _capability),
        _protocolError(),
      );
    });

    test(
      'reports revocation truthfully, including the retained-token limit',
      () async {
        final revoked =
            await _client(
              _FakeTransport(
                (_) async => _json(<String, dynamic>{
                  'revoked': true,
                  'reason': 'revoked',
                }),
              ),
            ).revokeManagementAuthorization(
              _transactionId,
              capability: _capability,
            );
        expect(revoked.revoked, isTrue);
        expect(revoked.retainedTokenMissing, isFalse);

        final notRetained =
            await _client(
              _FakeTransport(
                (_) async => _json(<String, dynamic>{
                  'revoked': false,
                  'reason': 'not_retained',
                }),
              ),
            ).revokeManagementAuthorization(
              _transactionId,
              capability: _capability,
            );
        expect(notRetained.revoked, isFalse);
        expect(notRetained.retainedTokenMissing, isTrue);

        await expectLater(
          _client(
            _FakeTransport(
              (_) async => _json(<String, dynamic>{'revoked': 'yes'}),
            ),
          ).revokeManagementAuthorization(
            _transactionId,
            capability: _capability,
          ),
          _protocolError(),
        );
      },
    );

    test('accepts the Worker-verified email confirmation redirect', () async {
      final transport = _FakeTransport(
        (_) async => _json(
          _snapshot(
            'ready',
            projectRef: _projectRef,
            runtimeConfig: <String, dynamic>{
              ..._runtimeConfig(),
              'emailConfirmationRedirect': 'https://worker.test/auth/confirmed',
            },
          ),
        ),
      );
      final snapshot = await _client(transport)
          .snapshot(_transactionId, capability: _capability);
      expect(
        snapshot.runtimeConfig?.emailConfirmationRedirect,
        'https://worker.test/auth/confirmed',
      );

      await expectLater(
        _client(
          _FakeTransport(
            (_) async => _json(
              _snapshot(
                'ready',
                projectRef: _projectRef,
                runtimeConfig: <String, dynamic>{
                  ..._runtimeConfig(),
                  'emailConfirmationRedirect':
                      'com.personalplanner.personalplanner://login-callback',
                },
              ),
            ),
          ),
        ).snapshot(_transactionId, capability: _capability),
        _protocolError(),
      );
    });
  });
}
