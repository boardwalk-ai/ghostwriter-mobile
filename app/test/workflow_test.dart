import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final failure in [false, true]) {
    testWidgets(
      failure
          ? 'start failure is visible to user'
          : 'prompt reaches API and streamed question appears',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var starts = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(const GhostWriterApp());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Start'));
            await tester.pumpAndSettle();
            expect(starts, 0, reason: 'Empty prompts must not start a run');
            await tester.enterText(
              find.byType(TextField).first,
              'Explain oceans',
            );
            await tester.tap(find.text('Start'));
            await tester.pumpAndSettle();
            expect(starts, 1);
            if (failure) {
              expect(
                find.textContaining('Could not start GhostWriter'),
                findsOneWidget,
              );
            } else {
              // The question appears in the conversation and as the input hint.
              expect(find.text('How many words?'), findsWidgets);
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((request) async {
            switch (request.url.path) {
              case '/api/ghostwriter/workspace':
                return http.Response(
                  '{"sessionName":"TEST","credits":10,"threads":[],"folders":[]}',
                  200,
                );
              case '/api/ghostwriter/start':
                starts++;
                expect(
                  jsonDecode(request.body)['draft']['instruction'],
                  'Explain oceans',
                );
                return failure
                    ? http.Response('Unavailable', 503)
                    : http.Response('{"runId":"test-run"}', 200);
              case '/api/ghostwriter/run':
                return http.Response(
                  'data: {"type":"question","field":"wordCount","question":"How many words?"}\n\n',
                  200,
                );
              default:
                throw StateError('Unexpected request: ${request.url}');
            }
          }),
        );
      },
    );
  }
}
