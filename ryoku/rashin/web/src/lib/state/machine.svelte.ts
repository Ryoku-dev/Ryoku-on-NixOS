// Live machine state every sheet can read: the daemon's status lamps and the
// vitals stream (/ws/vitals, a sample every two seconds). The status rides a
// slow poll because it only changes when something is installed or wired.

import { api, type Json } from "$lib/api/client";
import { JsonSocket } from "$lib/api/socket";

export interface Vitals {
  host: string;
  kernel: string;
  uptime: number;
  cpu: { model: string; cores: number; percent: number };
  mem: { total: number; used: number };
  disks: { mount: string; total: number; used: number }[];
  gpu?: { name: string; percent: number; vramUsed: number; vramTotal?: number };
}

export interface Status {
  enabled: boolean;
  running: boolean;
  port: number;
  ready: boolean;
  vault: { path: string; exists: boolean; files: number; lastIndexed: string };
  hermes: Json;
  agents: Json[];
}

export class MachineStore {
  vitals = $state<Vitals | null>(null);
  status = $state<Status | null>(null);
  /** the daemon answered /api/ping */
  online = $state(true);
  private socket: JsonSocket<Vitals> | null = null;
  private timer: number | null = null;

  start(): void {
    if (this.socket) return;
    this.socket = new JsonSocket<Vitals>({
      path: "/ws/vitals",
      onFrame: (v) => {
        this.vitals = v;
        this.online = true;
      },
      onClose: () => {
        void this.probe();
      },
    });
    this.socket.open();
    void this.refreshStatus();
    this.timer = window.setInterval(() => {
      if (!document.hidden) void this.refreshStatus();
    }, 30000);
  }

  stop(): void {
    this.socket?.close();
    this.socket = null;
    clearInterval(this.timer ?? undefined);
    this.timer = null;
  }

  async refreshStatus(): Promise<void> {
    try {
      this.status = (await api.status()) as unknown as Status;
      this.online = true;
    } catch {
      await this.probe();
    }
  }

  private async probe(): Promise<void> {
    this.online = await api.ping();
  }
}

export const machine = new MachineStore();
