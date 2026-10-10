"""Offline regression tests. All outbound HTTP is intercepted, even with real env keys."""
import asyncio
import json
import os
import unittest
from unittest.mock import AsyncMock, patch

import httpx

from app.tools import core, research, revision, executor
from app.memory.store import SemanticMemory
from app import main


class OfflineTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.send = AsyncMock(side_effect=AssertionError('Unexpected outbound HTTP'))
        def client_factory(**kwargs):
            kwargs.setdefault('transport', httpx.MockTransport(self.send))
            kwargs['trust_env'] = False
            return REAL_CLIENT(**kwargs)
        self.http = patch.object(httpx, 'AsyncClient', side_effect=client_factory)
        self.http.start()
        self.addCleanup(self.http.stop)

    async def test_model_requires_key_and_model(self):
        for config in ({}, {'OPENROUTER_API_KEY': 'fake-test-key'}):
            with self.subTest(config=config), patch.dict(os.environ, config, clear=True):
                with self.assertRaisesRegex(RuntimeError, 'configuration missing'):
                    await core.model_json('system', 'user')
        self.send.assert_not_awaited()

    async def test_model_request_and_json_response(self):
        captured = []
        async def respond(request, **kwargs):
            captured.append(request)
            return httpx.Response(200, request=request, json={
                'choices': [{'message': {'content': '```json\n{"ok": true}\n```'}}]})
        self.send.side_effect = respond
        with patch.dict(os.environ, OPENROUTER_API_KEY='fake-test-key', OPENROUTER_MODEL='test/model'):
            self.assertEqual(await core.model_json('system', 'prompt'), {'ok': True})
        payload = json.loads(captured[0].content)
        self.assertEqual(payload['model'], 'test/model')
        self.assertEqual(payload['messages'][1]['content'], 'prompt')
        self.assertEqual(captured[0].headers['authorization'], 'Bearer fake-test-key')

    async def test_model_http_failure_is_not_success(self):
        async def reject(request, **kwargs):
            return httpx.Response(429, request=request, json={'error': 'rate limited'})
        self.send.side_effect = reject
        with patch.dict(os.environ, OPENROUTER_API_KEY='fake', OPENROUTER_MODEL='test/model'):
            with self.assertRaises(httpx.HTTPStatusError):
                await core.model_json('system', 'prompt')

    async def test_model_invalid_output(self):
        for text, expected in [(' {"a": 1} ', {'a': 1}),
                               ('Here is JSON: {"a": 2}', {'a': 2}),
                               ('[1,2]', [1, 2])]:
            with self.subTest(text=text):
                self.assertEqual(core.parse_json_loose(text), expected)
        with self.assertRaisesRegex(ValueError, 'invalid JSON'):
            core.parse_json_loose('not JSON')

    async def test_planning_clamps_paragraph_count_and_records_topic(self):
        context = {'instruction': 'Explain oceans'}
        with patch.object(core, 'model_json', new=AsyncMock(return_value={
            'essayTopic': 'Oceans', 'paragraphCount': 100, 'searchQueries': list(range(10))})):
            await core.plan_essay({}, context)
        self.assertEqual(context['essayTopic'], 'Oceans')
        self.assertEqual(context['plan']['paragraphCount'], 12)
        self.assertEqual(len(context['plan']['searchQueries']), 6)

    async def test_writer_rejects_missing_inputs_without_network(self):
        for context in ({}, {'essayTopic': 'x'},
                        {'essayTopic': 'x', 'outlines': [1, 2, 3]}):
            with self.subTest(context=context), self.assertRaises(ValueError):
                await core.write_essay({}, context)
        self.send.assert_not_awaited()

    async def test_writer_stores_essay_and_bibliography(self):
        context = {'essayTopic': 'Oceans', 'outlines': ['a', 'b', 'c'],
                   'compactedSources': [{'summary': 'A source'}],
                   'draftSettings': {'wordCount': 100, 'citationStyle': 'APA'}}
        with patch.object(core, 'model_json', new=AsyncMock(return_value={
            'essay_content': 'Three word essay', 'bibliography': 'Source A'})):
            result = await core.write_essay({}, context)
        self.assertEqual(result['wordCount'], 3)
        self.assertEqual(context['bibliography'], 'Source A')
        self.assertEqual(context['essay'], 'Three word essay')

    async def test_research_filters_duplicates_and_unsupported_urls(self):
        context = {'essayTopic': 'x', 'outlines': ['a'],
                   'searchResults': [{'url': 'https://example.test/existing'}]}
        rows = [{'url': u} for u in ['https://example.test/existing', 'ftp://bad',
                'https://example.test/paper.pdf', 'https://example.test/new',
                'https://example.test/new']]
        with patch.object(research, 'model_json', new=AsyncMock(return_value={'results': rows})):
            result = await research.search_sources({}, context)
        self.assertEqual(result, {'added': 1, 'totalInContext': 2})

    async def test_scraping_counts_partial_failure(self):
        async def respond(request, **kwargs):
            if 'bad' in str(request.url):
                return httpx.Response(503, request=request)
            return httpx.Response(200, request=request, json={'fullContent': 'Evidence'})
        self.send.side_effect = respond
        context = {'searchResults': [{'url': 'https://example.test/good'},
                                     {'url': 'https://example.test/bad'}]}
        result = await research.scrape_sources({}, context)
        self.assertEqual(result, {'scraped': 1, 'failed': 1, 'totalInContext': 1})
        self.assertEqual(context['scrapedSources'][0]['fullContent'], 'Evidence')

    async def test_revision_changes_only_target_and_preserves_history(self):
        context = {'essay': 'First\n\nSecond', 'critiqueIssues': [
            {'paragraphIndex': 0}, {'paragraphIndex': 1}]}
        with patch.object(revision, 'model_json', new=AsyncMock(return_value={'paragraph': 'Revised'})):
            await revision.revise_paragraph({'paragraphIndex': 1, 'issue': 'clarity'}, context)
        self.assertEqual(context['essay'], 'First\n\nRevised')
        self.assertEqual(context['revisionHistory'][0]['before'], 'Second')
        self.assertEqual(context['critiqueIssues'], [{'paragraphIndex': 0}])

    async def test_revision_cap_and_invalid_index_do_not_call_model(self):
        result = await revision.revise_paragraph({}, {'revisionRounds': 8})
        self.assertTrue(result['capped'])
        with self.assertRaisesRegex(ValueError, 'paragraphIndex'):
            await revision.revise_paragraph({'paragraphIndex': 3}, {'essay': 'One'})
        self.send.assert_not_awaited()

    async def test_export_preserves_existing_metadata(self):
        context = {'essayTopic': 'Fallback', 'formatAnswers': {'author': 'A'}}
        result = await executor.execute_tool('finalize_export',
            {'finalEssayTitle': 'Title', 'author': '  '}, context)
        self.assertEqual(result['title'], 'Title')
        self.assertEqual(context['formatAnswers']['author'], 'A')
        self.assertTrue(context['exportReady'])
        with self.assertRaisesRegex(ValueError, 'not registered'):
            await executor.execute_tool('nonexistent', {}, {})

    async def test_http_routes_missing_run_and_demo_health(self):
        # ASGI transport exercises routes without a server or network sockets.
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app),
                                     base_url='http://test') as client:
            health = await client.get('/health')
            self.assertTrue(health.json()['demoMode'])
            for route, body in [('answer', {'field': 'x', 'value': 'y'}),
                                ('message', {'text': 'hello'}), ('pause', {}), ('cancel', {})]:
                response = await client.post('/runs/offline-missing/' + route, json=body)
                self.assertEqual(response.status_code, 404)

    async def test_answer_must_match_pending_question(self):
        run = {'pendingField': 'wordCount', 'answers': asyncio.Queue()}
        with patch.dict(main.runs, {'offline-test': run}, clear=True):
            with self.assertRaises(main.HTTPException) as error:
                await main.answer('offline-test', main.AnswerRequest(field='wrong', value=2))
            self.assertEqual(error.exception.status_code, 409)
            await main.answer('offline-test', main.AnswerRequest(field='wordCount', value=500))
            self.assertEqual(run['answers'].get_nowait(), {'field': 'wordCount', 'value': 500})

    async def test_memory_isolated_by_session(self):
        memory = SemanticMemory()
        memory.add('alice', 'Relevant', [1, 0])
        memory.add('alice', 'Other', [0, 1])
        memory.add('bob', 'Private', [1, 0])
        self.assertEqual([m.text for m in memory.search('alice', [1, 0], 1)], ['Relevant'])
        self.assertEqual(memory.search('unknown', [1, 0]), [])


REAL_CLIENT = httpx.AsyncClient

if __name__ == '__main__':
    unittest.main()
