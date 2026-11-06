#!/usr/bin/env node
// Generates SpellCheck's icons without any external dependencies.
//
// Outputs (all under App/Resources/):
//   MenuBarIconTemplate.png / @2x            default menu-bar glyph (black on transparent)
//   MenuBarIcons/<style>.png / @2x           all selectable menu-bar icon styles
//   AppIcon.iconset/*.png                    app icon (rounded diagonal gradient + white glyph)
//
// Styles:
//   omega-check  MDI "omega" glyph + Material "spellcheck" checkmark  (DEFAULT, FixKey-like)
//   omega        MDI "omega" alone
//   spellcheck   Material Symbols "spellcheck" (letter A + checkmark, the original)
//   checkmark    plain bold checkmark stroke
//
// Glyph sources:
//   Material Symbols spellcheck 24dp (Apache-2.0), MDI omega (Apache-2.0).
import { mkdirSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import zlib from 'zlib';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Material Symbols "spellcheck" 24dp — full path (letter A + checkmark)
const SPELLCHECK_D =
  'M14.1,22L9.85,17.75l1.4-1.4L14.1,19.2l5.65-5.65l1.4,1.4L14.1,22Z' +
  'M3,16L7.85,3H10.2l4.85,13h-2.3L11.6,12.7H6.35L5.2,16H3Zm4.05-5.2h3.9L9.05,5.4H8.95l-1.9,5.4Z';
// ...only the checkmark part:
const CHECK_D = 'M14.1,22L9.85,17.75l1.4-1.4L14.1,19.2l5.65-5.65l1.4,1.4L14.1,22Z';
// MDI "omega" 24dp (Apache-2.0, https://cdn.jsdelivr.net/gh/Templarian/MaterialDesign-SVG@master/svg/omega.svg)
const OMEGA_D =
  'M19.15,19H13.39V16.87C15.5,15.25 16.59,13.24 16.59,10.84C16.59,9.34 16.16,8.16 15.32,7.29' +
  'C14.47,6.42 13.37,6 12.03,6C10.68,6 9.57,6.42 8.71,7.3C7.84,8.17 7.41,9.37 7.41,10.88' +
  'C7.41,13.26 8.5,15.26 10.61,16.87V19H4.85V16.87H8.41C6.04,15.32 4.85,13.23 4.85,10.6' +
  'C4.85,8.5 5.5,6.86 6.81,5.66C8.12,4.45 9.84,3.85 11.97,3.85C14.15,3.85 15.89,4.45 17.19,5.64' +
  'C18.5,6.83 19.15,8.5 19.15,10.58C19.15,13.21 17.95,15.31 15.55,16.87H19.15V19Z';

// ---------- tiny PNG encoder ----------
const crcTable = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return ~c >>> 0;
}
function chunk(type, data) {
  const out = Buffer.alloc(8 + data.length + 4);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 'ascii');
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}
function encodePNG(width, height, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const stride = width * 4 + 1;
  const raw = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    raw[y * stride] = 0;
    rgba.copy(raw, y * stride + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

// ---------- SVG path parsing (M/L/H/V/C/S/Q/T/Z; curves flattened to polylines) ----------
function parsePath(d) {
  const tokens = d.match(/[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:e-?\d+)?/g);
  const subpaths = [];
  let cur = [], x = 0, y = 0, sx = 0, sy = 0, cmd = null, prevC2 = null, prevQ = null;
  let i = 0;
  const num = () => parseFloat(tokens[i++]);
  const cubic = (t) => {
    const mt = 1 - t;
    return [
      mt * mt * mt * x + 3 * mt * mt * t * prevC2[0] + 3 * mt * t * t * prevC2[2] + t * t * t * prevC2[4],
      mt * mt * mt * y + 3 * mt * mt * t * prevC2[1] + 3 * mt * t * t * prevC2[3] + t * t * t * prevC2[5],
    ];
  };
  const quad = (t) => {
    const mt = 1 - t;
    return [
      mt * mt * x + 2 * mt * t * prevQ[0] + t * t * prevQ[2],
      mt * mt * y + 2 * mt * t * prevQ[1] + t * t * prevQ[3],
    ];
  };
  while (i < tokens.length) {
    const t = tokens[i];
    if (/[MmLlHhVvCcSsQqTtAaZz]/.test(t)) {
      cmd = t;
      i++;
      if (cmd === 'Z' || cmd === 'z') {
        if (cur.length) { cur.push([sx, sy]); subpaths.push(cur); }
        cur = []; x = sx; y = sy; prevC2 = prevQ = null;
      }
      continue;
    }
    if (cmd === 'A' || cmd === 'a') throw new Error('arc commands not supported');
    const rel = cmd === cmd.toLowerCase();
    const ax = (v) => v + (rel ? x : 0);
    const ay = (v) => v + (rel ? y : 0);
    switch (cmd) {
      case 'M': case 'm': {
        const nx = ax(num()), ny = ay(num());
        if (cur.length) subpaths.push(cur);
        cur = [[nx, ny]]; x = nx; y = ny; sx = nx; sy = ny; prevC2 = prevQ = null;
        cmd = rel ? 'l' : 'L';
        break;
      }
      case 'L': case 'l': { const nx = ax(num()), ny = ay(num()); cur.push([nx, ny]); x = nx; y = ny; break; }
      case 'H': case 'h': { const nx = ax(num()); cur.push([nx, y]); x = nx; break; }
      case 'V': case 'v': { const ny = ay(num()); cur.push([x, ny]); y = ny; break; }
      case 'C': case 'c': {
        const c1x = ax(num()), c1y = ay(num()), c2x = ax(num()), c2y = ay(num()), nx = ax(num()), ny = ay(num());
        prevC2 = [c1x, c1y, c2x, c2y, nx, ny];
        for (let s = 1; s <= 16; s++) cur.push(cubic(s / 16));
        x = nx; y = ny; prevQ = null;
        break;
      }
      case 'S': case 's': {
        const r1x = prevC2 ? 2 * x - prevC2[2] : x, r1y = prevC2 ? 2 * y - prevC2[3] : y;
        const c2x = ax(num()), c2y = ay(num()), nx = ax(num()), ny = ay(num());
        prevC2 = [r1x, r1y, c2x, c2y, nx, ny];
        for (let s = 1; s <= 16; s++) cur.push(cubic(s / 16));
        x = nx; y = ny; prevQ = null;
        break;
      }
      case 'Q': case 'q': {
        const qx = ax(num()), qy = ay(num()), nx = ax(num()), ny = ay(num());
        prevQ = [qx, qy, nx, ny];
        for (let s = 1; s <= 12; s++) cur.push(quad(s / 12));
        x = nx; y = ny; prevC2 = null;
        break;
      }
      case 'T': case 't': {
        const rqx = prevQ ? 2 * x - prevQ[0] : x, rqy = prevQ ? 2 * y - prevQ[1] : y;
        const nx = ax(num()), ny = ay(num());
        prevQ = [rqx, rqy, nx, ny];
        for (let s = 1; s <= 12; s++) cur.push(quad(s / 12));
        x = nx; y = ny; prevC2 = null;
        break;
      }
    }
  }
  if (cur.length) subpaths.push(cur);
  return subpaths;
}

// scale + translate contours: p' = (x*s + tx, y*s + ty)
function transform(contours, s, tx, ty) {
  return contours.map((c) => c.map(([x, y]) => [x * s + tx, y * s + ty]));
}

function bbox(contours) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const c of contours) for (const [x, y] of c) {
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  return { minX, minY, maxX, maxY, w: maxX - minX, h: maxY - minY };
}

// fit contours into a target box (bottom-aligned, horizontally centered)
function fit(contours, box) {
  const b = bbox(contours);
  const s = Math.min(box.w / b.w, box.h / b.h);
  const tx = box.x + (box.w - b.w * s) / 2 - b.minX * s;
  const ty = box.y + box.h - b.maxY * s;
  return transform(contours, s, tx, ty);
}

// ---------- rasterizers ----------
// Filled renderer: supersampled scanline fill (nonzero winding), then box downsample.
function renderFilled(size, contourGroups, color, supersample = 4) {
  const buffers = contourGroups.map((contours) => renderFilledGroup(size, contours, color, supersample));
  return composite(size, buffers);
}

function renderFilledGroup(size, contours, color, supersample = 4) {
  const S = size * supersample;
  const segs = [];
  for (const c of contours) {
    for (let i = 0; i < c.length; i++) {
      const a = c[i], b = c[(i + 1) % c.length];
      segs.push([(a[0] / 24) * S, (a[1] / 24) * S, (b[0] / 24) * S, (b[1] / 24) * S]);
    }
  }
  const hi = Buffer.alloc(S * S * 4);
  for (let y = 0; y < S; y++) {
    const yc = y + 0.5;
    const xs = [];
    for (const [ax, ay, bx, by] of segs) {
      if ((ay <= yc) !== (by <= yc)) {
        xs.push([ax + ((yc - ay) / (by - ay)) * (bx - ax), by > ay ? 1 : -1]);
      }
    }
    xs.sort((p, q) => p[0] - q[0]);
    let wind = 0;
    for (let i = 0; i + 1 < xs.length; i++) {
      wind += xs[i][1];
      if (wind === 0) continue;
      const x0 = Math.max(0, Math.ceil(xs[i][0] - 0.5));
      const x1 = Math.min(S - 1, Math.floor(xs[i + 1][0] - 0.5));
      for (let x = x0; x <= x1; x++) {
        const o = (y * S + x) * 4;
        hi[o] = color[0]; hi[o + 1] = color[1]; hi[o + 2] = color[2]; hi[o + 3] = 255;
      }
    }
  }
  return downsample(hi, S, size, supersample);
}

// Stroke renderer: distance field to a polyline (round caps/joins), supersampled.
const CHECK = [[5.2, 12.6], [10.4, 17.8], [18.8, 7.4]];
const CHECK_STROKE = 3.1;
function distToSeg(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const l2 = dx * dx + dy * dy;
  let t = l2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}
function renderStroke(size, points, stroke, color, supersample = 4) {
  const S = size * supersample;
  const pts = points.map(([x, y]) => [(x / 24) * S, (y / 24) * S]);
  const half = ((stroke / 24) * S) / 2;
  const hi = Buffer.alloc(S * S * 4);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const px = x + 0.5, py = y + 0.5;
      let d = Infinity;
      for (let i = 0; i < pts.length - 1; i++) {
        d = Math.min(d, distToSeg(px, py, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]));
      }
      const alpha = Math.max(0, Math.min(1, half + 0.75 - d));
      if (alpha <= 0) continue;
      const o = (y * S + x) * 4;
      hi[o] = color[0]; hi[o + 1] = color[1]; hi[o + 2] = color[2];
      hi[o + 3] = Math.round(alpha * 255);
    }
  }
  return downsample(hi, S, size, supersample);
}

function downsample(hi, S, size, supersample) {
  const out = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let dy = 0; dy < supersample; dy++) {
        for (let dx = 0; dx < supersample; dx++) {
          const o = ((y * supersample + dy) * S + (x * supersample + dx)) * 4;
          r += hi[o]; g += hi[o + 1]; b += hi[o + 2]; a += hi[o + 3];
        }
      }
      const n = supersample * supersample, o = (y * size + x) * 4;
      out[o] = r / n; out[o + 1] = g / n; out[o + 2] = b / n; out[o + 3] = a / n;
    }
  }
  return out;
}

function composite(size, buffers) {
  const out = Buffer.alloc(size * size * 4);
  for (const buf of buffers) {
    for (let i = 0; i < out.length; i += 4) {
      const a = buf[i + 3];
      if (a > out[i + 3]) {
        out[i] = buf[i]; out[i + 1] = buf[i + 1]; out[i + 2] = buf[i + 2]; out[i + 3] = a;
      }
    }
  }
  return out;
}

// composite a white glyph over the rounded-rect diagonal gradient (app icon)
function renderAppIcon(size, glyphRGBA) {
  const SS = 4, S = size * SS;
  const rgba = Buffer.alloc(S * S * 4);
  const radius = 0.2267 * S;
  const cTop = [94, 177, 255], cBottom = [122, 90, 248]; // #5EB1FF -> #7A5AF8
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      let cov = 0;
      for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
        const px = x + dx / 2 + 0.25, py = y + dy / 2 + 0.25;
        const cx = Math.max(radius, Math.min(S - radius, px));
        const cy = Math.max(radius, Math.min(S - radius, py));
        if (Math.hypot(px - cx, py - cy) <= radius) cov++;
      }
      if (cov === 0) continue;
      const t = (x + y) / (2 * S);
      const o = (y * S + x) * 4;
      rgba[o] = cTop[0] + (cBottom[0] - cTop[0]) * t;
      rgba[o + 1] = cTop[1] + (cBottom[1] - cTop[1]) * t;
      rgba[o + 2] = cTop[2] + (cBottom[2] - cTop[2]) * t;
      rgba[o + 3] = (cov / 4) * 255;
    }
  }
  const glyphSize = Math.round(size * 0.62);
  const off = Math.floor((size - glyphSize) / 2);
  for (let y = 0; y < glyphSize; y++) {
    for (let x = 0; x < glyphSize; x++) {
      const go = (y * glyphSize + x) * 4;
      const a = glyphRGBA[go + 3];
      if (a === 0) continue;
      const o = ((y + off) * size + (x + off)) * 4;
      rgba[o] = 255; rgba[o + 1] = 255; rgba[o + 2] = 255;
      rgba[o + 3] = Math.max(rgba[o + 3], a);
    }
  }
  return rgba;
}

function writePNG(path, size, rgba) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, encodePNG(size, size, rgba));
  console.log('wrote', path);
}

// ---------- glyph definitions (24-unit grid) ----------
// Default: FixKey-style "Ω + checkmark" — MDI omega scaled into the letter slot
// of the Material spellcheck icon, next to the original checkmark.
// Ω at FULL size (the main symbol) with a smaller checkmark over its
// lower-right side — the classic spellcheck composition. The check must not
// shrink the Ω or obscure its recognizable shape.
const omegaFitted = fit(parsePath(OMEGA_D), { x: 2, y: 2, w: 20, h: 20 });
const checkFitted = fit(parsePath(CHECK_D), { x: 11.2, y: 12.0, w: 11.2, h: 10.4 });
// Knockout: an enlarged check silhouette is cut OUT of the \u03a9 (reversed
// contours under nonzero winding), then the check is drawn inside the gap.
// Both symbols stay readable at menu-bar size.
function reverseContour(c) { return c.slice().reverse(); }
function scaleAbout(contours, cx, cy, k) {
  return contours.map((c) => c.map(([x, y]) => [cx + (x - cx) * k, cy + (y - cy) * k]));
}
const checkBox = bbox(checkFitted);
const checkCx = checkBox.minX + checkBox.w / 2;
const checkCy = checkBox.minY + checkBox.h / 2;
const checkGap = scaleAbout(checkFitted, checkCx, checkCy, 1.24);
const OMEGA_CHECK = [
  omegaFitted.concat(checkGap.map(reverseContour)),
  checkFitted,
];

const GLYPHS = {
  'omega-check': { filled: OMEGA_CHECK },
  // Same full-size, same-scale fitted Ω as omega-check — the checkmark is
  // simply omitted (issue #7: Ω-only used to render substantially smaller).
  omega: { filled: [omegaFitted] },
  spellcheck: { filled: [parsePath(SPELLCHECK_D)] },
  checkmark: { stroke: { points: CHECK, width: CHECK_STROKE } },
};

function renderGlyph(style, size, color) {
  const g = GLYPHS[style];
  if (!g) throw new Error('unknown style ' + style);
  if (g.filled) return renderFilled(size, g.filled, color, 8);
  return renderStroke(size, g.stroke.points, g.stroke.width, color, 8);
}

// ---------- vector emit: SVG source + template PDF ----------
// The PDF is the asset the app actually ships: true vector geometry, so the
// menu-bar glyph stays razor sharp on any Retina display (the old 22px PNG
// was upscaled on Retina — that was the "low resolution" look). The SVG
// files are the human-editable source artwork.
const PDF_PT = 18; // menu-bar point size of the final image
const PDF_SCALE = PDF_PT / 24;

function fmt(n) { return (Math.round(n * 100) / 100).toString(); }

function contoursToPathData(contours) {
  let d = '';
  for (const c of contours) {
    if (!c.length) continue;
    d += `M${fmt(c[0][0])} ${fmt(c[0][1])}`;
    for (let i = 1; i < c.length; i++) d += `L${fmt(c[i][0])} ${fmt(c[i][1])}`;
    d += 'Z';
  }
  return d;
}

function writeSVG(path, style) {
  const g = GLYPHS[style];
  let body = '';
  if (g.filled) {
    for (const group of g.filled) {
      body += `  <path d="${contoursToPathData(group)}" fill="#000"/>\n`;
    }
  } else {
    const pts = g.stroke.points.map(([x, y]) => `${fmt(x)} ${fmt(y)}`).join(' ');
    body += `  <path d="M${pts}" fill="none" stroke="#000" stroke-width="${g.stroke.width}" stroke-linecap="round" stroke-linejoin="round"/>\n`;
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">\n${body}</svg>\n`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, svg);
  console.log('wrote', path);
}

function pdfCoords([x, y]) {
  // SVG y-down to PDF y-up, scaled into points.
  return [x * PDF_SCALE, PDF_PT - y * PDF_SCALE];
}

function pdfContent(style) {
  const g = GLYPHS[style];
  let ops = '0 0 0 rg\n';
  if (g.filled) {
    for (const group of g.filled) {
      for (const c of group) {
        if (!c.length) continue;
        const [x0, y0] = pdfCoords(c[0]);
        ops += `${fmt(x0)} ${fmt(y0)} m\n`;
        for (let i = 1; i < c.length; i++) {
          const [x, y] = pdfCoords(c[i]);
          ops += `${fmt(x)} ${fmt(y)} l\n`;
        }
        ops += 'h\n';
      }
      ops += 'f\n';
    }
  } else {
    const w = g.stroke.width * PDF_SCALE;
    ops += `1 J 1 j\n${fmt(w)} w\n`;
    const pts = g.stroke.points.map(pdfCoords);
    ops += `${fmt(pts[0][0])} ${fmt(pts[0][1])} m\n`;
    for (let i = 1; i < pts.length; i++) {
      ops += `${fmt(pts[i][0])} ${fmt(pts[i][1])} l\n`;
    }
    ops += 'S\n';
  }
  return ops;
}

function writePDF(path, style) {
  const content = pdfContent(style);
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PDF_PT} ${PDF_PT}] /Resources << >> /Contents 4 0 R >>`,
    `<< /Length ${content.length} >>\nstream\n${content}endstream`,
  ];
  let out = '%PDF-1.4\n';
  const offsets = [];
  objects.forEach((o, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) out += `${String(off).padStart(10, '0')} 00000 n \n`;
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, out, 'latin1');
  console.log('wrote', path);
}

// ---------- emit ----------
const DEFAULT_STYLE = 'omega-check';
const BLACK = [0, 0, 0];

// default menu-bar template (backwards-compatible name)
writePNG(join(ROOT, 'App/Resources/MenuBarIconTemplate.png'), 22, renderGlyph(DEFAULT_STYLE, 22, BLACK));
writePNG(join(ROOT, 'App/Resources/MenuBarIconTemplate@2x.png'), 44, renderGlyph(DEFAULT_STYLE, 44, BLACK));

// all selectable styles: vector PDF (primary asset) + SVG source + PNG fallback
for (const style of Object.keys(GLYPHS)) {
  writePDF(join(ROOT, `App/Resources/MenuBarIcons/${style}.pdf`), style);
  writeSVG(join(ROOT, `App/Resources/MenuBarIcons/svg/${style}.svg`), style);
  writePNG(join(ROOT, `App/Resources/MenuBarIcons/${style}.png`), 22, renderGlyph(style, 22, BLACK));
  writePNG(join(ROOT, `App/Resources/MenuBarIcons/${style}@2x.png`), 44, renderGlyph(style, 44, BLACK));
  // Review previews: the exact Retina menu-bar pixel size (36px = 18pt @2x)
  // plus an 8x enlargement so the shapes can be judged without a Mac.
  const previews = join(ROOT, 'docs/icon-previews');
  writePNG(join(previews, `${style}-menubar-18pt@2x.png`), 36, renderGlyph(style, 36, BLACK));
  writePNG(join(previews, `${style}-preview-144px.png`), 144, renderGlyph(style, 144, BLACK));
}

// app iconset: gradient + white default glyph
const iconset = join(ROOT, 'App/Resources/AppIcon.iconset');
for (const s of [16, 32, 128, 256, 512]) {
  const glyph = renderGlyph(DEFAULT_STYLE, Math.round(s * 0.62), [255, 255, 255]);
  writePNG(join(iconset, `icon_${s}x${s}.png`), s, renderAppIcon(s, glyph));
  const glyph2 = renderGlyph(DEFAULT_STYLE, Math.round(s * 2 * 0.62), [255, 255, 255]);
  writePNG(join(iconset, `icon_${s}x${s}@2x.png`), s * 2, renderAppIcon(s * 2, glyph2));
}
console.log('done');
