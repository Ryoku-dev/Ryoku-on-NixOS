import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('./displaybar.js', import.meta.url), 'utf8'), ctx);

test('a per-output style overrides the global style', () => {
    const displays = {bar_style: {'DP-1': 'chroma', 'HDMI-A-1': ''}};
    assert.equal(ctx.styleFor(displays, 'DP-1', 'qsbar'), 'chroma');
    assert.equal(ctx.styleFor(displays, 'HDMI-A-1', 'qsbar'), 'qsbar');
    assert.equal(ctx.styleFor(displays, 'DP-2', 'sumi'), 'sumi');
});

test('a per-output widget override falls back to the style default', () => {
    const displays = {
        bar_widgets: {
            'DP-1': {chroma: {media: false, clock: true}}
        }
    };
    assert.equal(ctx.widgetEnabled(displays, 'DP-1', 'chroma', 'media', true), false);
    assert.equal(ctx.widgetEnabled(displays, 'DP-1', 'chroma', 'clock', false), true);
    assert.equal(ctx.widgetEnabled(displays, 'DP-1', 'chroma', 'network', true), true);
    assert.equal(ctx.widgetEnabled(displays, 'HDMI-A-1', 'chroma', 'media', false), false);
});

test('global iris is exclusive and old per-output iris overrides are inert', () => {
    const config = {bar_style: {'DP-1': 'chroma', 'DP-2': 'iris'}};
    assert.equal(ctx.styleFor(config, 'DP-1', 'iris'), 'iris');
    assert.equal(ctx.styleFor(config, 'DP-2', 'qsbar'), 'qsbar');
});

test('shared QS Bar is hosted when selected only on a secondary output', () => {
    const screens = [{name: 'DP-1'}, {name: 'HDMI-A-1'}];
    const config = {bar_style: {'HDMI-A-1': 'qsbar'}};
    assert.equal(ctx.styleFor(config, 'DP-1', 'sumi'), 'sumi');
    assert.equal(ctx.styleFor(config, 'HDMI-A-1', 'sumi'), 'qsbar');
    assert.equal(ctx.hasStyle(config, screens, 'sumi', 'qsbar'), true);
    assert.equal(ctx.hasStyle(config, screens, 'sumi', 'iris'), false);
    assert.equal(ctx.hasStyle(config, screens, 'iris', 'qsbar'), false);
});
