import {expect, test} from 'bun:test';
import {readFileSync} from 'node:fs';

test('metadata UUID is claudemonitor@assista', () => {
    const metadata = JSON.parse(readFileSync('extension/metadata.json', 'utf-8'));
    expect(metadata.uuid).toBe('claudemonitor@assista');
});
