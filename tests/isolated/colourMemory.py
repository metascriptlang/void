from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(path, before, after):
    text = path.read_text(encoding='utf-8')
    if text.count(before) != 1:
        raise RuntimeError(f'{path}: expected one allocator seam, found {text.count(before)}')
    path.write_text(text.replace(before, after), encoding='utf-8')


def bad_png(source, target):
    raw = source.read_bytes()
    mutated = bytearray(raw)
    offset = 0
    patches = 0
    while True:
        start = raw.find(b'\x89PNG\r\n\x1a\n', offset)
        if start < 0:
            break
        cursor = start + 8
        while cursor + 12 <= len(raw):
            size = int.from_bytes(raw[cursor:cursor + 4], 'big')
            tag = raw[cursor + 4:cursor + 8]
            if tag == b'IDAT' and size >= 2:
                mutated[cursor + 8:cursor + 10] = b'\x00\x00'
                patches += 1
                break
            if tag == b'IEND':
                break
            cursor += size + 12
        offset = start + 8
    if patches == 0:
        raise RuntimeError('no PNG IDAT fixture found')
    target.write_bytes(mutated)


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = Path.cwd().resolve()
    source = args.source_root.resolve()
    template = source / 'tests/isolated/colourMemory'
    out = root / 'out/colourMemory'
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=out)).resolve()
    shutil.copytree(source / 'src', work / 'src')
    (work / 'deps').symlink_to(root / 'deps', target_is_directory=True)
    for name in ('colourAllocFault.h', 'colourAllocFault.c', 'colourAllocProbe.ms'):
        shutil.copyfile(template / name, work / name)
    for name in ('layout.ms', 'node.ms'):
        replace_once(work / 'src/void2d' / name, '"../../../yoga/src/index"',
                     json.dumps((root.parent / 'yoga/src/index').as_posix()))
    glyph = work / 'src/void2d/glyph.c'
    replace_once(glyph, '#include "glyph.h"',
                 '#include "glyph.h"\n#include "../../colourAllocFault.h"')
    replace_once(glyph, '(unsigned char *)calloc((size_t)lw * (size_t)lh, 1)',
                 '(unsigned char *)retryColourLayerCalloc((size_t)lw * (size_t)lh, 1)')
    colour = work / 'src/void2d/colourEmoji/colourFace.c'
    replace_once(colour, 'static int pngNoMemory;',
                 '#include "../../../colourAllocFault.h"\nstatic int pngNoMemory;')
    replace_once(colour, 'void *data = malloc(size);',
                 'void *data = retryColourPngMalloc(size);')
    replace_once(colour, 'void *data = realloc(ptr, size);',
                 'void *data = retryColourPngRealloc(ptr, 0, size);')
    replace_once(colour, 'static unsigned premultiplied(unsigned c, unsigned a)',
                 'const char *retryColourPngReason(void) { return pngReason(); }\n\n'
                 'static unsigned premultiplied(unsigned c, unsigned a)')
    replace_once(colour,
                 '(unsigned int *)malloc(sizeof(unsigned int) * (size_t)w * (size_t)h)',
                 '(unsigned int *)retryColourSourceMalloc('
                 'sizeof(unsigned int) * (size_t)w * (size_t)h)')
    bad_png(source / 'tests/fonts/sbixSynthetic.ttf', work / 'badPng.ttf')
    environment = dict(os.environ, MSC_NO_GLOBAL_CACHE='1',
                       VOID_COLOUR_BAD_PNG=str(work / 'badPng.ttf'))
    command = [os.environ.get('MSC', 'msc'), 'test', str(work / 'colourAllocProbe.ms'),
               '-d:voidColourEmoji']
    log = work / 'test.log'
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=root, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    (work / 'test.exit').write_text(str(result.returncode) + '\n')
    text = re.sub(r'\x1b\[[0-9;]*m', '', log.read_text(encoding='utf-8', errors='replace'))
    proof = {'command': command, 'actualExit': result.returncode, 'logSha256': digest(log),
             'sourceHashes': {p.relative_to(source).as_posix(): digest(p)
                              for p in sorted((source / 'src').rglob('*')) if p.is_file()},
             'templateHashes': {name: digest(template / name) for name in
                                ('colourAllocFault.h', 'colourAllocFault.c', 'colourAllocProbe.ms')}}
    (work / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(f'colour memory evidence: {work}')
    summary = re.search(r'^\s*Tests\s+(\d+) passed \((\d+)\)\s*$', text, re.MULTILINE)
    markers = [f'colour allocation stage {stage}: recovered=true dirty=false'
               for stage in (1, 2, 3)]
    if result.returncode != 0 or not summary or summary[1] != summary[2] or any(
            text.count(marker) != 1 for marker in markers):
        print(text[-6000:])
        return 1
    if 'colour permanent PNG reason:' not in text:
        print('FAIL colour memory: missing malformed-PNG control')
        return 1
    print('PASS colour memory: layer, source and PNG allocations recover; malformed PNG stays idle')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
