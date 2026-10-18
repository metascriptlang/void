import os
from pathlib import Path
import re
import subprocess
import sys

ENTRY = 'tests/isolated/rangeSpan/probe.ms'


def check_refusal(code, stdout, stderr, stream):
    out = re.sub(r'\x1b\[[0-9;]*m', '', stdout)
    err = re.sub(r'\x1b\[[0-9;]*m', '', stderr)
    assert stream in ['ui', 'saved'] and code == 1, (stream, code)
    before = 'NOTE_RANGE_BEFORE ' + stream
    assert out.splitlines().count(before) == 1
    assert 'NOTE_RANGE_RETURNED' not in out + err
    message = 'void2d: incomplete or unaddressable UI span in noteRange'
    assert out.splitlines().count(message) == 1 and out.index(before) < out.index(message)
    assert err.splitlines().count('Error: unreachable') == 1
    assert not re.search(r'Tests\s+\d+ passed|failed|error:|link failed|undefined symbol', out + err)
    return {'stream': stream, 'classification': 'runtime-span-refusal', 'exit': 1}


def main():
    if sys.flags.optimize:
        raise RuntimeError('refuse optimized Python')
    sys.stdout.reconfigure(encoding='utf-8')
    compiler = os.environ.get('MSC', 'msc')
    directory = Path('out/rangeSpan')
    directory.mkdir(parents=True, exist_ok=True)
    for mode in ['debug', 'release']:
        for stream in ['ui', 'saved']:
            command = [compiler, 'test']
            if mode == 'release':
                command.append('--release')
            command.append(ENTRY)
            environment = os.environ.copy()
            environment['VOID_NOTE_RANGE_SPAN'] = stream
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=environment)
            stem = directory / (mode + '-' + stream)
            stem.with_suffix('.stdout').write_bytes(result.stdout)
            stem.with_suffix('.stderr').write_bytes(result.stderr)
            stem.with_suffix('.exit').write_text(str(result.returncode) + '\n')
            check_refusal(result.returncode, result.stdout.decode('utf-8'),
                          result.stderr.decode('utf-8'), stream)
    print('PASS noteRange spans: current/saved refused in debug/release')


if __name__ == '__main__':
    main()
