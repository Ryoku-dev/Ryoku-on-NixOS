// Escape-first markdown for vault docs and agent replies. Every byte is
// HTML-escaped before any transform runs, so hostile input can never break out
// of the escaped text; the span and block rules only ever add trusted markup
// around already-neutralised content. Pure logic, vitest-covered.

export function escapeHtml(s: unknown): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export function escapeAttr(s: unknown): string {
  return escapeHtml(s).replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function splitRow(line: string): string[] {
  let s = line.trim();
  if (s.startsWith("|")) s = s.slice(1);
  if (s.endsWith("|")) s = s.slice(0, -1);
  return s.split("|").map((c) => c.trim());
}

function isTableSep(line: string): boolean {
  if (!line.includes("|")) return false;
  const cells = splitRow(line);
  return cells.length > 0 && cells.every((c) => /^:?-{1,}:?$/.test(c));
}

// Spans run on already-escaped text. Inline code and finished links are lifted
// out into sentinels first so later passes (bold/italic, bare-URL autolinking)
// can never reach inside them; everything is spliced back at the end.
function inline(src: string): string {
  const holds: string[] = [];
  const stash = (html: string) => "\u0000" + (holds.push(html) - 1) + "\u0000";
  let s = src;

  s = s.replace(/`([^`]+)`/g, (_, c: string) => stash("<code>" + c + "</code>"));

  // Markdown links. http(s) open a new tab hardened with rel=noopener; in-page
  // #anchors stay same-tab; anything else (javascript:, data:) is left as text.
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (whole: string, text: string, rawHref: string) => {
    const href = rawHref.trim();
    if (/^https?:\/\//i.test(href)) {
      return stash('<a href="' + href.replace(/"/g, "%22") + '" target="_blank" rel="noopener">' + text + "</a>");
    }
    if (href[0] === "#") {
      return stash('<a href="' + href.replace(/"/g, "%22") + '">' + text + "</a>");
    }
    return whole;
  });

  // Bare http(s) URLs in the remaining text. Stops at whitespace, a sentinel,
  // or an escaped angle bracket; trailing sentence punctuation ).,;:!? is
  // peeled off the match and left as plain text after the link.
  s = s.replace(/https?:\/\/[^\s\u0000<]+/gi, (match: string) => {
    let url = match;
    let tail = "";
    while (/[).,;:!?]$/.test(url)) {
      tail = url.slice(-1) + tail;
      url = url.slice(0, -1);
    }
    if (!url) return tail;
    return stash('<a href="' + url.replace(/"/g, "%22") + '" target="_blank" rel="noopener">' + url + "</a>") + tail;
  });

  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/\*([^*]+)\*/g, "<em>$1</em>");

  // Splice sentinels back. Loop because a stashed link's text may itself hold
  // an inline-code sentinel, and one replace pass does not rescan its output.
  let prev: string;
  do {
    prev = s;
    s = s.replace(/\u0000(\d+)\u0000/g, (_, i: string) => holds[Number(i)] ?? "");
  } while (s !== prev);
  return s;
}

export interface MarkdownOptions {
  /** hard line breaks inside a paragraph (agent replies); vault docs soft-wrap */
  breaks?: boolean;
}

interface ListState {
  type: "ul" | "ol";
  items: string[];
}

export function mdToHtml(src: string, opts?: MarkdownOptions): string {
  const lines = escapeHtml(src).split(/\r?\n/);
  const out: string[] = [];
  let para: string[] = [];
  let list: ListState | null = null;
  let quote: string[] = [];
  const brk = opts?.breaks ? "<br>" : " ";

  const flushPara = () => {
    if (para.length) {
      out.push("<p>" + inline(para.join(brk)) + "</p>");
      para = [];
    }
  };
  const flushList = () => {
    if (list) {
      out.push("<" + list.type + ">" + list.items.map((it) => "<li>" + inline(it) + "</li>").join("") + "</" + list.type + ">");
      list = null;
    }
  };
  const flushQuote = () => {
    if (quote.length) {
      out.push("<blockquote>" + mdToHtml(quote.join("\n"), opts).replace(/\n/g, "") + "</blockquote>");
      quote = [];
    }
  };
  const flushAll = () => {
    flushPara();
    flushList();
    flushQuote();
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? "";

    // HTML comment-only lines (the vault's generated-fence markers) are
    // plumbing, not content; hide them. They arrive escaped by this point.
    if (/^\s*&lt;!--.*--&gt;\s*$/.test(line)) continue;

    const fence = /^\s*```\s*([\w+-]*)\s*$/.exec(line);
    if (fence) {
      flushAll();
      const buf: string[] = [];
      i++;
      while (i < lines.length && !/^\s*```/.test(lines[i] ?? "")) buf.push(lines[i++] ?? "");
      const lang = fence[1] ? ' data-lang="' + escapeAttr(fence[1]) + '"' : "";
      out.push("<pre" + lang + "><code>" + buf.join("\n") + "</code></pre>");
      continue;
    }

    const q = /^\s*&gt;\s?(.*)$/.exec(line);
    if (q) {
      flushPara();
      flushList();
      quote.push(q[1] ?? "");
      continue;
    }
    flushQuote();

    if (/^\s*-{3,}\s*$/.test(line)) {
      flushAll();
      out.push("<hr>");
      continue;
    }

    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    if (h) {
      flushAll();
      const level = (h[1] ?? "#").length;
      out.push("<h" + level + ">" + inline((h[2] ?? "").trim()) + "</h" + level + ">");
      continue;
    }

    if (line.includes("|") && i + 1 < lines.length && isTableSep(lines[i + 1] ?? "")) {
      flushAll();
      const header = splitRow(line);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && (lines[i] ?? "").includes("|") && (lines[i] ?? "").trim() !== "") {
        rows.push(splitRow(lines[i++] ?? ""));
      }
      i--;
      let t = "<table><thead><tr>" + header.map((c) => "<th>" + inline(c) + "</th>").join("") + "</tr></thead>";
      if (rows.length) {
        t += "<tbody>" + rows.map((r) => "<tr>" + r.map((c) => "<td>" + inline(c) + "</td>").join("") + "</tr>").join("") + "</tbody>";
      }
      out.push(t + "</table>");
      continue;
    }

    let m = /^\s*[-*]\s+(.*)$/.exec(line);
    if (m) {
      flushPara();
      if (!list || list.type !== "ul") {
        flushList();
        list = { type: "ul", items: [] };
      }
      list.items.push(m[1] ?? "");
      continue;
    }
    m = /^\s*\d+\.\s+(.*)$/.exec(line);
    if (m) {
      flushPara();
      if (!list || list.type !== "ol") {
        flushList();
        list = { type: "ol", items: [] };
      }
      list.items.push(m[1] ?? "");
      continue;
    }

    if (line.trim() === "") {
      flushPara();
      flushList();
      continue;
    }

    flushList();
    para.push(line.trim());
  }
  flushAll();
  return out.join("\n");
}
