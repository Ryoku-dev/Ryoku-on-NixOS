// Libraries.dev ships its effects as React components. Two of them (the
// border beam and the bot avatars) are driven by the package's own shared
// clocks and material caches, so they are rendered as they ship: a React
// root inside a Svelte-owned element. Nothing else in the console is React;
// this file is the whole seam.

import { createElement, type ComponentType } from "react";
import { createRoot, type Root } from "react-dom/client";

export interface Island<P> {
  render(props: P): void;
  destroy(): void;
}

export function mountIsland<P extends object>(host: HTMLElement, component: ComponentType<P>): Island<P> {
  const root: Root = createRoot(host);
  return {
    render(props: P) {
      root.render(createElement(component, props));
    },
    destroy() {
      // React refuses a synchronous unmount from inside a render; the next
      // tick is always outside one.
      setTimeout(() => root.unmount(), 0);
    },
  };
}
