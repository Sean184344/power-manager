#!/usr/bin/env python3
"""Render selected baseline VCD signals as standalone SVG timing diagrams.

This reader supports the scalar/vector subset emitted by the baseline Icarus
testbench. It intentionally rejects a changed timescale or missing top signals.
"""
import argparse
from html import escape
from pathlib import Path

SIGNALS = ['state', 'sleep_req', 'wake', 'idle', 'ready', 'clk_en',
           'isolate', 'block_work', 'fault']
STATES = ['RUN', 'DRAIN', 'ISOLATE', 'SLEEP', 'START', 'RELEASE', 'FAULT']


def read_vcd(path):
    lines = path.read_text().splitlines()
    if '$timescale 1ps $end' not in ' '.join(' '.join(lines).split()):
        raise ValueError('Expected baseline VCD timescale of 1ps')
    scope, codes, events = [], {}, {}
    time = 0
    for raw in lines:
        line = raw.strip()
        fields = line.split()
        if line.startswith('$scope'):
            scope.append(fields[2])
        elif line.startswith('$upscope'):
            scope.pop()
        elif line.startswith('$var') and scope == ['tb_power_manager']:
            name = fields[4]
            if name in SIGNALS:
                codes[fields[3]] = name
                events[name] = []
        elif line.startswith('#'):
            time = int(line[1:]) / 1000
        elif line.startswith('b'):
            value, code = line[1:].split()
            if code in codes:
                events[codes[code]].append((time, value))
        elif line and line[0] in '01xz' and line[1:] in codes:
            events[codes[line[1:]]].append((time, line[0]))
    if set(events) != set(SIGNALS):
        raise ValueError('Missing baseline top-level signals')
    return events


def render(events, start, end, title, notes, output):
    left, width, row = 130, 1020, 43
    height = 130 + row * len(SIGNALS)
    def x(time):
        return left + (time - start) / (end - start) * width
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1180 {height}" role="img">',
           f'<title>{escape(title)}</title>',
           '<rect width="100%" height="100%" fill="white"/>',
           '<g font-family="monospace" font-size="12" fill="#172b4d">',
           f'<text x="16" y="24" font-size="18">{escape(title)}</text>']
    for t in range(int(start), int(end) + 1, 5):
        svg += [f'<path d="M{x(t):.1f},55 V{height-70}" stroke="#e5e9ef"/>',
                f'<text x="{x(t):.1f}" y="47" text-anchor="middle">{t}</text>']
    for i, name in enumerate(SIGNALS):
        y = 80 + i * row
        svg.append(f'<text x="12" y="{y+5}">{name}</text>')
        value = 'x'
        for t, v in events[name]:
            if t <= start:
                value = v
        points = [(start, value)] + [(t, v) for t, v in events[name] if start < t < end]
        points.append((end, points[-1][1]))
        for j, ((t, v), (next_t, _)) in enumerate(zip(points, points[1:])):
            if name == 'state':
                label = STATES[int(v, 2)] if set(v) <= {'0', '1'} and int(v, 2) < 7 else v
                svg += [f'<rect x="{x(t):.1f}" y="{y-12}" width="{x(next_t)-x(t):.1f}" height="24" fill="#edf4ff" stroke="#3267a8"/>',
                        f'<text x="{(x(t)+x(next_t))/2:.1f}" y="{y+4}" text-anchor="middle">{label}</text>']
            else:
                level = y - 10 if v == '1' else y + 10
                svg.append(f'<path d="M{x(t):.1f},{level} H{x(next_t):.1f}" stroke="#146b58" fill="none" stroke-width="2"/>')
                if j and v != points[j-1][1]:
                    svg.append(f'<path d="M{x(t):.1f},{y-10} V{y+10}" stroke="#146b58" stroke-width="2"/>')
                if v not in ('0', '1'):
                    svg.append(f'<text x="{x(t)+4:.1f}" y="{y}">{v}</text>')
    for i, note in enumerate(notes):
        svg.append(f'<text x="16" y="{height-42+i*18}">{escape(note)}</text>')
    svg.append('</g></svg>')
    output.write_text('\n'.join(svg) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vcd', type=Path, default=Path('reports/m6/baseline.vcd'))
    parser.add_argument('--output', type=Path, default=Path('docs/images'))
    args = parser.parse_args()
    events = read_vcd(args.vcd)
    args.output.mkdir(parents=True, exist_ok=True)
    render(events, 30, 115, 'Normal sleep / wake (time in ns)',
           ['55 ns: isolation asserted; 65 ns: clock disable requested.',
            '95 ns: ready accepted; RELEASE guard lasts until work admission at 105 ns.'],
           args.output / 'sleep-wake.svg')
    render(events, 675, 750, 'Clock-start timeout (TIMEOUT_CYCLES=4; time in ns)',
           ['685 ns: wake enters START. Four wait edges: 695, 705, 715, 725 ns.',
            '725 ns: sticky FAULT. Ready arriving at 730 ns cannot release work.'],
           args.output / 'start-timeout.svg')


if __name__ == '__main__':
    main()
