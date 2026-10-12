// Characters XML 1.0 forbids outright; a track name carrying one would leave
// the whole image unparseable, not just mislabelled.
const invalidXml = /[^\t\n\r\x20-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/gu;

export const escapeXml = (value: string): string =>
  value
    .replace(invalidXml, "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");

export const num = (value: number): string =>
  String(Math.round(value * 100) / 100);

type Attrs = Record<string, string | number | undefined | null | false>;

const attrs = (values: Attrs): string =>
  Object.entries(values)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => ` ${k}="${typeof v === "number" ? num(v) : escapeXml(v)}"`)
    .join("");

export const el = (
  name: string,
  values: Attrs = {},
  ...children: string[]
): string =>
  children.length === 0
    ? `<${name}${attrs(values)}/>`
    : `<${name}${attrs(values)}>${children.join("")}</${name}>`;

export const text = (values: Attrs, content: string): string =>
  `<text${attrs(values)}>${escapeXml(content)}</text>`;

// No font metrics server-side, so fitting and truncation work from an
// average glyph width that errs wide for the system sans faces.
export const textWidth = (
  content: string,
  size: number,
  letterSpacing = 0,
): number => content.length * (size * 0.58 + letterSpacing);

export const fit = (
  content: string,
  size: number,
  width: number,
  letterSpacing = 0,
): string | null => {
  if (textWidth(content, size, letterSpacing) <= width) return content;
  const chars = Math.floor(width / (size * 0.58 + letterSpacing)) - 1;
  if (chars < 3) return null;
  return content.slice(0, chars).trimEnd() + "…";
};
