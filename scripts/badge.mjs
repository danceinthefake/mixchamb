#!/usr/bin/env node
// Tiny SVG badge generator. Outputs a shields.io-style flat
// badge to stdout given a label, a value, and an optional color.
// Used by CI to render coverage badges into the `badges` orphan
// branch — no third-party rendering service.
//
// Usage:
//   node scripts/badge.mjs --label "elixir coverage" --value "87%"
//   node scripts/badge.mjs --label foo --value bar --color "#4c1"

const args = parseArgs(process.argv.slice(2))
const label = args.label ?? "label"
const value = args.value ?? "value"
const color = args.color ?? autoColor(value)

// Crude width estimation. Verdana 11px averages ~6.6 px/char for
// alphanumerics; we add a 10 px gutter on each side.
const charWidth = 6.6
const sidePadding = 10
const labelWidth = Math.round(label.length * charWidth + sidePadding * 2)
const valueWidth = Math.round(value.length * charWidth + sidePadding * 2)
const totalWidth = labelWidth + valueWidth

const labelTextX = labelWidth / 2
const valueTextX = labelWidth + valueWidth / 2

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${totalWidth}" height="20" role="img" aria-label="${escapeXml(label)}: ${escapeXml(value)}">
  <title>${escapeXml(label)}: ${escapeXml(value)}</title>
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r">
    <rect width="${totalWidth}" height="20" rx="3" fill="#fff"/>
  </clipPath>
  <g clip-path="url(#r)">
    <rect width="${labelWidth}" height="20" fill="#555"/>
    <rect x="${labelWidth}" width="${valueWidth}" height="20" fill="${color}"/>
    <rect width="${totalWidth}" height="20" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
    <text aria-hidden="true" x="${labelTextX * 10}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="${(labelWidth - sidePadding * 2) * 10}">${escapeXml(label)}</text>
    <text x="${labelTextX * 10}" y="140" transform="scale(.1)" fill="#fff" textLength="${(labelWidth - sidePadding * 2) * 10}">${escapeXml(label)}</text>
    <text aria-hidden="true" x="${valueTextX * 10}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="${(valueWidth - sidePadding * 2) * 10}">${escapeXml(value)}</text>
    <text x="${valueTextX * 10}" y="140" transform="scale(.1)" fill="#fff" textLength="${(valueWidth - sidePadding * 2) * 10}">${escapeXml(value)}</text>
  </g>
</svg>
`

process.stdout.write(svg)

// ── helpers ────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = {}
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2)
      out[key] = argv[i + 1]
      i++
    }
  }
  return out
}

function autoColor(value) {
  // Numeric with optional trailing % → greyscale gradient. Anything
  // non-numeric gets a neutral blue.
  const m = String(value).match(/^([\d.]+)/)
  if (!m) return "#007ec6"
  const n = Number(m[1])
  if (n >= 90) return "#4c1"
  if (n >= 80) return "#97ca00"
  if (n >= 70) return "#a4a61d"
  if (n >= 60) return "#dfb317"
  if (n >= 50) return "#fe7d37"
  return "#e05d44"
}

function escapeXml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;")
}
