import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/ghostwriter_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final api = GhostWriterApi(baseUrl: 'http://offline.test');

  test('start posts instruction and returns run identifier', () async {
    await http.runWithClient(
      () async {
        expect(await api.start('Explain oceans'), 'run-1');
      },
      () => MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/ghostwriter/start');
        expect(jsonDecode(request.body), {
          'draft': {'instruction': 'Explain oceans'},
        });
        return http.Response('{"runId":"run-1"}', 200);
      }),
    );
  });

  test('workspace preserves saved conversations', () async {
    await http.runWithClient(
      () async {
        final state = await api.workspace();
        expect((state['threads'] as List).single['essay'], 'Saved essay');
      },
      () => MockClient((request) async {
        expect(request.url.path, '/api/ghostwriter/workspace');
        return http.Response('{"threads":[{"essay":"Saved essay"}]}', 200);
      }),
    );
  });

  test('answer and run controls use correct routes and payloads', () async {
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await api.answer(runId: 'r', field: 'wordCount', value: 500);
        await api.message(runId: 'r', text: 'Revise');
        await api.pause('r');
        await api.cancel('r');
      },
      () => MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    expect(requests.map((r) => r.url.path), [
      '/api/ghostwriter/answer',
      '/api/ghostwriter/runs/r/message',
      '/api/ghostwriter/pause',
      '/api/ghostwriter/cancel',
    ]);
    expect(jsonDecode(requests[0].body), {
      'runId': 'r',
      'field': 'wordCount',
      'value': 500,
    });
    expect(jsonDecode(requests[1].body), {'text': 'Revise'});
    expect(jsonDecode(requests[2].body), {'runId': 'r'});
    expect(jsonDecode(requests[3].body), {'runId': 'r'});
  });

  test('save sends essay and citation metadata', () async {
    await http.runWithClient(
      () async {
        final saved = await api.saveThread(
          title: 'Title',
          prompt: 'Prompt',
          status: 'Finished',
          essay: 'Essay',
          bibliography: 'Source',
          citationStyle: 'APA',
          wordCount: 1,
          folderId: 'folder',
          runId: 'run',
          sources: [
            {'url': 'https://example.test'},
          ],
        );
        expect(saved['id'], 'saved');
      },
      () => MockClient((request) async {
        expect(request.url.path, '/api/ghostwriter/threads');
        final body = jsonDecode(request.body);
        expect(body['essay'], 'Essay');
        expect(body['bibliography'], 'Source');
        expect(body['citationStyle'], 'APA');
        expect(body['folderId'], 'folder');
        expect(body['sources'], [
          {'url': 'https://example.test'},
        ]);
        return http.Response('{"id":"saved"}', 200);
      }),
    );
  });

  test('event stream decodes fragmented UTF-8 and ignores keepalives', () async {
    await http.runWithClient(
      () async {
        expect(await api.events('r').toList(), [
          {'type': 'text', 'text': 'café'},
          {'type': 'done'},
        ]);
      },
      () => MockClient.streaming((request, body) async {
        expect(request.headers['Accept'], 'text/event-stream');
        final bytes = utf8.encode(
          ': keepalive\n\ndata: {"type":"text","text":"café"}\n\ndata: {"type":"done"}\n\n',
        );
        return http.StreamedResponse(
          Stream.fromIterable(bytes.map((b) => [b])),
          200,
        );
      }),
    );
  });

  test('event stream exposes HTTP failure', () async {
    await http.runWithClient(() async {
      await expectLater(api.events('missing').toList(), throwsException);
    }, () => MockClient((_) async => http.Response('missing', 404)));
  });

  test('invalid stream JSON fails rather than pretending completion', () async {
    await http.runWithClient(() async {
      await expectLater(api.events('r').toList(), throwsFormatException);
    }, () => MockClient((_) async => http.Response('data: invalid\n\n', 200)));
  });

  for (final status in [400, 401, 429, 500]) {
    test(
      'HTTP $status propagates across start workspace and controls',
      () async {
        await http.runWithClient(() async {
          await expectLater(api.start('Prompt'), throwsException);
          await expectLater(api.workspace(), throwsException);
          await expectLater(api.pause('r'), throwsException);
          await expectLater(api.createFolder('Folder'), throwsException);
        }, () => MockClient((_) async => http.Response('Failure', status)));
      },
    );
  }
}
