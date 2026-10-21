#!/usr/bin/env python3
"""Resident Redux inference worker and whisper-cli-compatible Voxtype client."""
import argparse
import array
import ctypes as c
import json
import errno
import math
import stat
import os
from pathlib import Path
import signal
import socket
import socketserver
import sys
import time
import wave

DEFAULT_MODEL = Path.home() / '.local/share/voxtype/models/redux-packed.gguf'
DEFAULT_LIBRARY = Path.home() / '.local/lib/voxtype-parakeet/libparakeet.so'
VERSION = "0.2.0"
MAX_MESSAGE = 1024 * 1024


def socket_path():
    override = os.environ.get('VOXTYPE_REDUX_SOCKET')
    if override:
        return override
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if not runtime:
        raise RuntimeError('XDG_RUNTIME_DIR is required')
    return str(Path(runtime) / 'voxtype-redux' / 'worker.sock')


def read_message(stream):
    line = stream.readline(MAX_MESSAGE + 1)
    if not line.endswith(b'\n') or len(line) > MAX_MESSAGE:
        raise ValueError('missing or oversized JSON message')
    return json.loads(line)


class CppEngine:
    def __init__(self, model=DEFAULT_MODEL, library=DEFAULT_LIBRARY, pool_threads=0, chunk_seconds=0):
        self.chunk_seconds = chunk_seconds
        self.lib = c.CDLL(str(library))
        signatures = {
            'abi_version': ([], c.c_int),
            'load': ([c.c_char_p], c.c_void_p),
            'load_error': ([], c.c_char_p),
            'last_error': ([c.c_void_p], c.c_char_p),
            'transcribe_pcm': ([c.c_void_p, c.POINTER(c.c_float), c.c_int, c.c_int, c.c_int], c.c_void_p),
            'free_string': ([c.c_void_p], None),
            'free': ([c.c_void_p], None),
        }
        for name, (args, result) in signatures.items():
            fn = getattr(self.lib, 'parakeet_capi_' + name)
            fn.argtypes, fn.restype = args, result
        if self.lib.parakeet_capi_abi_version() < 10:
            raise RuntimeError('parakeet.cpp ABI 10 or later is required')
        self.context = self.lib.parakeet_capi_load(os.fsencode(model))
        if not self.context:
            raise RuntimeError(self.lib.parakeet_capi_load_error())
        if pool_threads:
            fn = self.lib.parakeet_capi_set_concurrency
            fn.argtypes, fn.restype = [c.c_void_p, c.c_int, c.c_int], c.c_int
            if fn(self.context, 2, pool_threads) == 0:
                error = self.lib.parakeet_capi_last_error(self.context)
                self.close()
                raise RuntimeError(error)

    def transcribe(self, path):
        with wave.open(str(path), 'rb') as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 16000):
                raise ValueError('expected mono, signed 16-bit PCM WAV at 16 kHz')
            pcm = array.array('h', wav.readframes(wav.getnframes()))
        if sys.byteorder != 'little':
            pcm.byteswap()
        if not pcm:
            raise ValueError('audio is empty')
        if self.chunk_seconds and len(pcm) > self.chunk_seconds * 16000:
            texts = []
            start = 0
            while start < len(pcm):
                end = min(len(pcm), start + int(self.chunk_seconds * 16000))
                if end < len(pcm):
                    # Choose a quiet 20ms frame in the last 3s, without reference text.
                    candidates = range(max(start + 16000, end - 48000), end, 320)
                    end = min(candidates, key=lambda i: sum(v*v for v in pcm[i:i+320])) + 160
                texts.append(self._transcribe_pcm(pcm[start:end]))
                start = end
            return ' '.join(t for t in texts if t)
        return self._transcribe_pcm(pcm)

    def _transcribe_pcm(self, pcm):
        samples = (c.c_float * len(pcm))(*(value / 32768.0 for value in pcm))
        output = self.lib.parakeet_capi_transcribe_pcm(self.context, samples, len(pcm), 16000, 0)
        if not output:
            raise RuntimeError(self.lib.parakeet_capi_last_error(self.context))
        try:
            return c.string_at(output).decode('utf-8').strip()
        finally:
            self.lib.parakeet_capi_free_string(output)

    def close(self):
        if self.context:
            self.lib.parakeet_capi_free(self.context)
            self.context = None


class PhotonEngine:
    def __init__(self, model='moondream/parakeet-redux', **unused):
        import moondream as md
        self.model = md.photon(str(model), device='cpu')

    def transcribe(self, path):
        return self.model.transcribe(audio=str(path))['text'].strip()

    def close(self):
        self.model.close()


def request(payload, path=None):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(180)
        client.connect(path or socket_path())
        client.sendall(json.dumps(payload).encode() + b'\n')
        with client.makefile('rb') as stream:
            response = read_message(stream)
    if not response.get('ok'):
        raise RuntimeError(response.get('error', 'worker failed'))
    return response


def serve(args):
    path = Path(args.socket or socket_path())
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.parent.stat().st_uid != os.getuid():
        raise RuntimeError('socket directory is not owned by the current user')
    os.chmod(path.parent, 0o700)
    # Recover only an owned, stale socket; refuse regular files, symlinks and live workers.
    try:
        old = path.lstat()
    except FileNotFoundError:
        old = None
    if old is not None:
        if not stat.S_ISSOCK(old.st_mode) or old.st_uid != os.getuid():
            raise RuntimeError(f'refusing to replace non-owned or non-socket path: {path}')
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.5)
            try:
                probe.connect(str(path))
            except OSError as error:
                if error.errno not in (errno.ECONNREFUSED, errno.ENOENT):
                    raise
                try:
                    current = path.lstat()
                    if (current.st_ino, current.st_dev) != (old.st_ino, old.st_dev):
                        raise RuntimeError('socket changed during stale-socket recovery')
                    path.unlink()
                except FileNotFoundError:
                    pass
            else:
                try:
                    probe.sendall(b'{"command":"status"}\n')
                    probe.recv(MAX_MESSAGE)
                except OSError:
                    pass
                raise RuntimeError(f'worker already running: {path}')
    start = time.perf_counter()
    if args.backend == 'cpp':
        engine = CppEngine(args.model or DEFAULT_MODEL, args.library, args.pool_threads, args.chunk_seconds)
    else:
        engine = PhotonEngine(args.model or 'moondream/parakeet-redux')
    load_seconds = time.perf_counter() - start

    class Handler(socketserver.StreamRequestHandler):
        timeout = 180
        def handle(self):
            try:
                payload = read_message(self.rfile)
                if payload.get('command') == 'status':
                    response = {'ok': True, 'backend': args.backend, 'load_seconds': load_seconds, 'model': str(args.model or ('moondream/parakeet-redux' if args.backend == 'photon' else DEFAULT_MODEL)),
                                'pool_threads': args.pool_threads, 'chunk_seconds': args.chunk_seconds}
                elif payload.get('command') == 'transcribe':
                    requested_model = payload.get('model')
                    expected_model = Path(args.model or DEFAULT_MODEL) if args.backend == 'cpp' else Path(args.compat_model or DEFAULT_MODEL)
                    if requested_model and Path(requested_model).resolve() != expected_model.resolve():
                        raise ValueError('requested model differs from worker model')
                    audio = Path(payload['audio']).resolve(strict=True)
                    start = time.perf_counter()
                    text = engine.transcribe(audio)
                    response = {'ok': True, 'text': text, 'backend': args.backend,
                                'inference_seconds': time.perf_counter() - start}
                else:
                    raise ValueError('unknown worker command')
            except Exception as error:
                response = {'ok': False, 'error': str(error)}
            self.wfile.write(json.dumps(response).encode() + b'\n')

    server = None
    def stop(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        server = socketserver.UnixStreamServer(str(path), Handler)
        os.chmod(path, 0o600)
        print(json.dumps({'ready': True, 'backend': args.backend, 'load_seconds': load_seconds}), flush=True)
        notify_socket = os.environ.get('NOTIFY_SOCKET')
        if notify_socket:
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notifier:
                address = '\0' + notify_socket[1:] if notify_socket.startswith('@') else notify_socket
                notifier.sendto(b'READY=1', address)
        server.serve_forever(poll_interval=0.2)
    finally:
        if server:
            server.server_close()
            path.unlink(missing_ok=True)
        engine.close()


def main():
    if sys.argv[1:] == ['--version']:
        print(f'voxtype-redux {VERSION}')
        return
    if len(sys.argv) > 1 and sys.argv[1] == 'serve':
        parser = argparse.ArgumentParser(description='Resident local Redux worker')
        parser.add_argument('serve')
        parser.add_argument('--backend', choices=['cpp', 'photon'], default='cpp')
        parser.add_argument('--model')
        parser.add_argument('--compat-model', help='Photon only: expected GGUF path in stock Voxtype CLI requests')
        parser.add_argument('--library', default=str(DEFAULT_LIBRARY))
        parser.add_argument('--socket')
        parser.add_argument('--pool-threads', type=int, choices=[0, 1, 2, 4], default=0, help='Use two native backend slots, N compute threads each; zero uses native defaults')
        parser.add_argument('--chunk-seconds', type=float, default=0, help='Split long CPP input near quiet frames; zero disables splitting')
        args = parser.parse_args()
        if args.backend != 'photon' and args.compat_model:
            parser.error('--compat-model applies only to the Photon backend')
        if args.backend == 'photon' and args.model not in (None, 'moondream/parakeet-redux'):
            parser.error('Photon backend is restricted to moondream/parakeet-redux')
        if not math.isfinite(args.chunk_seconds) or (args.chunk_seconds != 0 and args.chunk_seconds < 5):
            parser.error('--chunk-seconds must be zero or a finite number >= 5')
        serve(args)
        return
    if len(sys.argv) > 1 and sys.argv[1] == 'status':
        print(json.dumps(request({'command': 'status'})))
        return
    parser = argparse.ArgumentParser(description='whisper-cli protocol adapter for stock Voxtype')
    parser.add_argument('--model', required=True, help='Voxtype compatibility field; worker selects its model')
    parser.add_argument('--file', required=True)
    parser.add_argument('--output-json', action='store_true', required=True)
    parser.add_argument('--output-file', required=True)
    parser.add_argument('--threads', type=int, help='Compatibility field; worker uses backend default threads')
    parser.add_argument('--no-prints', action='store_true')
    parser.add_argument('--language', default='en', choices=['en', 'auto'], help='English/auto pipeline; Redux detects language')
    parser.add_argument('--translate', action='store_true')
    parser.add_argument('--prompt')
    args = parser.parse_args()
    if args.translate or args.prompt:
        parser.error('translation and prompting are unsupported by this adapter')
    audio = Path(args.file).resolve(strict=True)
    result = request({'command': 'transcribe', 'audio': str(audio), 'model': args.model})
    destination = Path(args.output_file + '.json')
    destination.write_text(json.dumps({'transcription': [{'text': result['text']}]}) + '\n')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'voxtype-redux: {error}', file=sys.stderr)
        sys.exit(1)
