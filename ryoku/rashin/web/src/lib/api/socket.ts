// A WebSocket that keeps itself open: the daemon restarts on updates, and a
// console left on screen must pick the new one up without a reload. Frames
// are JSON lines in both directions; the backoff is capped so a dead daemon
// costs one probe every few seconds, not a storm.

import { wsUrl } from "./client";

export interface SocketOptions<T> {
  path: string;
  onFrame: (frame: T) => void;
  onOpen?: () => void;
  onClose?: () => void;
}

export class JsonSocket<T> {
  private ws: WebSocket | null = null;
  private closed = false;
  private attempt = 0;
  private timer: number | null = null;
  private readonly opts: SocketOptions<T>;

  constructor(opts: SocketOptions<T>) {
    this.opts = opts;
  }

  open(): void {
    this.closed = false;
    this.connect();
  }

  get live(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  send(frame: unknown): boolean {
    if (!this.live) return false;
    this.ws!.send(JSON.stringify(frame));
    return true;
  }

  close(): void {
    this.closed = true;
    clearTimeout(this.timer ?? undefined);
    this.timer = null;
    this.ws?.close();
    this.ws = null;
  }

  private connect(): void {
    const ws = new WebSocket(wsUrl(this.opts.path));
    this.ws = ws;
    ws.onopen = () => {
      this.attempt = 0;
      this.opts.onOpen?.();
    };
    ws.onmessage = (e: MessageEvent<string>) => {
      let frame: T;
      try {
        frame = JSON.parse(e.data) as T;
      } catch {
        return;
      }
      this.opts.onFrame(frame);
    };
    ws.onclose = () => {
      if (this.ws === ws) this.ws = null;
      this.opts.onClose?.();
      this.retry();
    };
    ws.onerror = () => ws.close();
  }

  private retry(): void {
    if (this.closed || this.timer) return;
    const delay = Math.min(8000, 400 * 2 ** this.attempt++);
    this.timer = window.setTimeout(() => {
      this.timer = null;
      if (!this.closed) this.connect();
    }, delay);
  }
}
