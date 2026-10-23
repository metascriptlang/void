import { test } from 'node:test';
import assert from 'node:assert/strict';
import { benchRows, pageFor } from './webBench.mjs';

test('benchRows keeps the name value rows of a console log and drops the rest', () => {
	const logs = [
		'ui.nodes 20000',
		'ui.present.ms 3.25\r',
		'warning: something',
		'ui.draws 7\nui.uploadBytes 1.5e+06',
		'EXCEPTION boom',
		'ui.firstPaint.ms -0.5',
		'RENDERER ANGLE (NVIDIA)',
		'ui.bad 12abc',
	];
	assert.deepEqual(benchRows(logs), ['ui.nodes 20000', 'ui.present.ms 3.25', 'ui.draws 7', 'ui.uploadBytes 1.5e+06', 'ui.firstPaint.ms -0.5']);
});

test('pageFor loads the scene script', () => {
	assert.match(pageFor('Ui'), /src="benchUi\.js"/);
});
