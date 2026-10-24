import { describe, expect, test } from "vitest";
import { escapeHtml, mdToHtml } from "./markdown";

describe("markdown", () => {
  test("escapes html entities", () => {
    expect(escapeHtml("a < b & c > d")).toBe("a &lt; b &amp; c &gt; d");
  });

  test("hostile script input stays escaped", () => {
    const html = mdToHtml("<script>alert('x')</script>");
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  test("html comment-only lines are hidden, inline comments stay escaped text", () => {
    expect(mdToHtml("<!-- rashin:generated:begin -->\nbody\n<!-- rashin:generated:end -->")).toBe("<p>body</p>");
    expect(mdToHtml("before <!-- x --> after")).toContain("&lt;!-- x --&gt;");
  });

  test("headings render by level", () => {
    expect(mdToHtml("# Title")).toBe("<h1>Title</h1>");
    expect(mdToHtml("### Deep")).toBe("<h3>Deep</h3>");
    expect(mdToHtml("##### TooDeep")).toBe("<p>##### TooDeep</p>");
  });

  test("bold and italic and inline code", () => {
    expect(mdToHtml("**b** and *i*")).toBe("<p><strong>b</strong> and <em>i</em></p>");
    expect(mdToHtml("use `x = 1` here")).toBe("<p>use <code>x = 1</code> here</p>");
  });

  test("inline code content is escaped, not transformed", () => {
    expect(mdToHtml("`<b>*no*</b>`")).toContain("<code>&lt;b&gt;*no*&lt;/b&gt;</code>");
  });

  test("fenced code block keeps its language and escapes its body", () => {
    expect(mdToHtml("```\nline1\n<tag>\n```")).toBe("<pre><code>line1\n&lt;tag&gt;</code></pre>");
    expect(mdToHtml("```sh\nls\n```")).toBe('<pre data-lang="sh"><code>ls</code></pre>');
  });

  test("http links allowed, javascript scheme rejected", () => {
    expect(mdToHtml("[go](https://x.io)")).toBe('<p><a href="https://x.io" target="_blank" rel="noopener">go</a></p>');
    expect(mdToHtml("[anchor](#top)")).toBe('<p><a href="#top">anchor</a></p>');
    const bad = mdToHtml("[x](javascript:alert(1))");
    expect(bad).not.toContain("<a ");
    expect(bad).toContain("[x]");
  });

  test("bare url becomes a target=_blank link and peels trailing punctuation", () => {
    expect(mdToHtml("see https://ryoku.dev/docs for more")).toContain(
      '<a href="https://ryoku.dev/docs" target="_blank" rel="noopener">https://ryoku.dev/docs</a>',
    );
    const html = mdToHtml("(see https://ryoku.dev/x).");
    expect(html).toContain('<a href="https://ryoku.dev/x" target="_blank" rel="noopener">https://ryoku.dev/x</a>).');
    expect(html).not.toContain('href="https://ryoku.dev/x).');
  });

  test("bare url inside inline code is left untouched", () => {
    const html = mdToHtml("run `curl https://ryoku.dev` now");
    expect(html).toContain("<code>curl https://ryoku.dev</code>");
    expect(html).not.toContain("<a ");
  });

  test("bare javascript scheme is never linkified", () => {
    expect(mdToHtml("javascript:alert(1) is inert")).not.toContain("<a ");
  });

  test("pipe table renders thead and tbody", () => {
    const html = mdToHtml("| A | B |\n| - | - |\n| 1 | 2 |");
    expect(html).toContain("<table>");
    expect(html).toContain("<th>A</th><th>B</th>");
    expect(html).toContain("<td>1</td><td>2</td>");
  });

  test("horizontal rule, lists and blockquotes", () => {
    expect(mdToHtml("---")).toBe("<hr>");
    expect(mdToHtml("- a\n- b")).toBe("<ul><li>a</li><li>b</li></ul>");
    expect(mdToHtml("1. a\n2. b")).toBe("<ol><li>a</li><li>b</li></ol>");
    expect(mdToHtml("> quoted **words**\n> more")).toBe("<blockquote><p>quoted <strong>words</strong> more</p></blockquote>");
  });

  test("blank line separates paragraphs; breaks opt in to hard line breaks", () => {
    expect(mdToHtml("one\n\ntwo")).toBe("<p>one</p>\n<p>two</p>");
    expect(mdToHtml("one\ntwo", { breaks: true })).toBe("<p>one<br>two</p>");
  });
});
