import 'dart:io';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  MembershipWorkerClient client(http.Response Function(http.Request) handler) =>
      MembershipWorkerClient(
        baseUrl: 'https://worker.test',
        tokenProvider: () async => 'token-value-not-logged',
        client: MockClient((request) async => handler(request)),
      );

  test('maps all membership statuses without granting access', () async {
    http.Request? sentRequest;
    final result = await client((request) {
      sentRequest = request;
      return http.Response('''{"memberships":[
        {"instituteId":"a","role":"teacher","status":"active"},
        {"instituteId":"b","role":"instituteAdmin","status":"pending"},
        {"instituteId":"c","role":"parent","status":"rejected"},
        {"instituteId":"d","role":"teacher","status":"suspended"},
        {"instituteId":"e","role":"parent","status":"revoked"}
      ]}''', 200);
    }).loadOwnMemberships('current-user');

    expect(sentRequest?.method, 'POST');
    expect(sentRequest?.url.path, '/v1/memberships/list');
    expect(sentRequest?.headers['authorization'], startsWith('Bearer '));
    expect(result, hasLength(5));
    expect(result.first.isActive, isTrue);
    expect(result[1].status, InstituteMembershipStatus.pending);
    expect(result[2].status, InstituteMembershipStatus.rejected);
    expect(result[3].status, InstituteMembershipStatus.suspended);
    expect(result[4].status, InstituteMembershipStatus.revoked);
  });

  test('maps unauthorized and malformed responses to safe failures', () async {
    await expectLater(
      client((_) => http.Response('{}', 401)).loadOwnMemberships('current'),
      throwsA(isA<MembershipWorkerFailure>()),
    );
    await expectLater(
      client((_) => http.Response('{bad', 200)).loadOwnMemberships('current'),
      throwsA(isA<MembershipWorkerFailure>()),
    );
  });

  test(
    'maps network and backend failures without leaking transport details',
    () async {
      await expectLater(
        client(
          (_) => throw const SocketException('network'),
        ).loadOwnMemberships('current'),
        throwsA(isA<MembershipWorkerFailure>()),
      );
      await expectLater(
        client((_) => http.Response('{}', 503)).loadOwnMemberships('current'),
        throwsA(isA<MembershipWorkerFailure>()),
      );
    },
  );

  test('never exposes a token in safe failures', () async {
    const token = 'token-value-not-logged';
    final worker = MembershipWorkerClient(
      baseUrl: 'https://worker.test',
      tokenProvider: () async => token,
      client: MockClient((_) async => http.Response(token, 503)),
    );

    await expectLater(
      worker.loadOwnMemberships('current'),
      throwsA(
        isA<MembershipWorkerFailure>().having(
          (failure) => failure.message,
          'message',
          isNot(contains(token)),
        ),
      ),
    );
  });

  test(
    'uses only safe join, status, review and revoke Worker payloads',
    () async {
      final calls = <http.Request>[];
      final worker = client((request) {
        calls.add(request);
        if (request.url.path.endsWith('/request')) {
          return http.Response('{"status":"pending"}', 202);
        }
        if (request.url.path.endsWith('/requests/list') ||
            request.url.path.endsWith('/reviewable')) {
          return http.Response(
            '{"requests":[{"requestId":"request-a","instituteId":"institute-a","requestedRole":"teacher","status":"pending"}]}',
            200,
          );
        }
        return http.Response(
          request.url.path.endsWith('/revoke')
              ? '{"status":"revoked"}'
              : '{"status":"active"}',
          200,
        );
      });

      expect(
        (await worker.requestMembership(
          joinCode: 'ABCDEF',
          requestedRole: UserRole.teacher,
        )).status,
        InstituteMembershipStatus.pending,
      );
      expect((await worker.loadOwnRequests()).single.requestId, 'request-a');
      expect(
        (await worker.loadReviewableRequests()).single.requestedRole,
        UserRole.teacher,
      );
      expect(
        await worker.reviewRequest(requestId: 'request-a', approve: true),
        InstituteMembershipStatus.active,
      );
      expect(
        await worker.revokeMembership('member-a'),
        InstituteMembershipStatus.revoked,
      );
      expect(
        calls.map((value) => value.url.path),
        containsAll(<String>[
          '/v1/memberships/request',
          '/v1/memberships/requests/list',
          '/v1/memberships/reviewable',
          '/v1/memberships/review',
          '/v1/memberships/revoke',
        ]),
      );
      for (final call in calls) {
        expect(call.headers['authorization'], isNot(contains('request-a')));
      }
    },
  );
}
