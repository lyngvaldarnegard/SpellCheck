#!/usr/bin/env node
// Generates SpellCheck's icons without any external dependencies:
//   App/Resources/AppIcon.iconset/*.png   (app icon, rounded gradient square + white glyph)
//   App/Resources/MenuBarIconTemplate.png / @2x  (menu-bar template glyph, black on transparent)
// The glyph is the Material Symbols "spellcheck" 24dp path.
import { mkdirSync, writeFileSync, readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import zlib from 'zlib';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SVG = process.argv[2];

const PATH_D = SVG
  ? readFileSync(SVG, 'utf8').match(/<path d="([^"]+)"/)[1]
  : 'M14.1,22L9.85,17.75l1.4-1.4L14.1,19.2l5.65-5.65l1.4,1.4L14.1,22ZM3,16L7.85,3H10.2l4.85,13h-2.3L11.6,12.7H6.35L5.2,16H3Zm4.05-5.2h3.9L9.05,5.4H8.95l-1.9,5.4Z';

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

// ---------- SVG path parsing (M/L/H/V/Z, absolute + relative) ----------
function parsePath(d) {
  const tokens = d.match(/[MmLlHhVvZz]|-?\d*\.?\d+(?:e-?\d+)?/g);
  const subpaths = [];
  let cur = [], x = 0, y = 0, sx = 0, sy = 0, cmd = null;
  let i = 0;
  const num = () => parseFloat(tokens[i++]);
  while (i < tokens.length) {
    const t = tokens[i];
    if (/[MmLlHhVvZz]/.test(t)) {
      cmd = t;
      i++;
      if (cmd === 'Z' || cmd === 'z') {
        cur.push([sx, sy]);
        subpaths.push(cur);
        cur = [];
      }
      continue;
    }
    const rel = cmd === cmd.toLowerCase();
    switch (cmd) {
      case 'M': case 'm': {
        const nx = num() + (rel ? x : 0), ny = num() + (rel ? y : 0);
        if (cur.length) subpaths.push(cur);
        cur = [[nx, ny]]; x = nx; y = ny; sx = nx; sy = ny;
        cmd = rel ? 'l' : 'L';
        break;
      }
      case 'L': case 'l': { const nx = num() + (rel ? x : 0), ny = num() + (rel ? y : 0); cur.push([nx, ny]); x = nx; y = ny; break; }
      case 'H': case 'h': { const nx = num() + (rel ? x : 0); cur.push([nx, y]); x = nx; break; }
      case 'V': case 'v': { const ny = num() + (rel ? y : 0); cur.push([x, ny]); y = ny; break; }
    }
  }
  if (cur.length) subpaths.push(cur);
  return subpaths;
}

// ---------- rasterizer: nonzero winding scanline fill, supersampled ----------
function renderGlyph(size, color, supersample = 4) {
  const S = size * supersample;
  const subpaths = parsePath(PATH_D).map(sp => sp.map(([px, py]) => [(px / 24) * S, (py / 24) * S]));
  const rgba = Buffer.alloc(S * S * 4);
  const edges = [];
  for (const sp of subpaths) {
    for (let i = 0; i < sp.length - 1; i++) {
      const [x1, y1] = sp[i], [x2, y2] = sp[i + 1];
      if (y1 !== y2) edges.push([x1, y1, x2, y2, Math.sign(y2 - y1)]);
    }
  }
  for (let y = 0; y < S; y++) {
    const yc = y + 0.5;
    const xs = [];
    for (const [x1, y1, x2, y2, dir] of edges) {
      if ((y1 <= yc && y2 > yc) || (y2 <= yc && y1 > yc)) {
        xs.push([x1 + ((yc - y1) / (y2 - y1)) * (x2 - x1), dir]);
      }
    }
    xs.sort((a, b) => a[0] - b[0]);
    let winding = 0;
    let start = 0;
    for (const [x, dir] of xs) {
      const prev = winding;
      winding += dir;
      if (prev === 0 && winding !== 0) start = x;
      else if (prev !== 0 && winding === 0) {
        const x0 = Math.max(0, Math.floor(start)), x1 = Math.min(S - 1, Math.ceil(x));
        for (let px = x0; px <= x1; px++) {
          const o = (y * S + px) * 4;
          rgba[o] = color[0]; rgba[o + 1] = color[1]; rgba[o + 2] = color[2]; rgba[o + 3] = 255;
        }
      }
    }
  }
  // downsample
  const out = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let dy = 0; dy < supersample; dy++) {
        for (let dx = 0; dx < supersample; dx++) {
          const o = ((y * supersample + dy) * S + (x * supersample + dx)) * 4;
          r += rgba[o]; g += rgba[o + 1]; b += rgba[o + 2]; a += rgba[o + 3];
        }
      }
      const n = supersample * supersample, o = (y * size + x) * 4;
      out[o] = r / n; out[o + 1] = g / n; out[o + 2] = b / n; out[o + 3] = a / n;
    }
  }
  return out;
}

// composite glyph (white) over rounded-rect gradient background
function renderAppIcon(size) {
  const SS = 4, S = size * SS;
  const rgba = Buffer.alloc(S * S * 4);
  const radius = 0.2267 * S;
  const cTop = [99, 102, 241], cBottom = [124, 58, 237]; // indigo-500 -> violet-600
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      // rounded rect mask (supersampled coverage via distance check at 2x2 subsamples)
      let cov = 0;
      for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
        const px = x + dx / 2 + 0.25, py = y + dy / 2 + 0.25;
        const cx = Math.max(radius, Math.min(S - radius, px));
        const cy = Math.max(radius, Math.min(S - radius, py));
        const d = Math.hypot(px - cx, py - cy);
        if (d <= radius) cov++;
      }
      if (cov === 0) continue;
      const t = y / S;
      const o = (y * S + x) * 4;
      rgba[o] = cTop[0] + (cBottom[0] - cTop[0]) * t;
      rgba[o + 1] = cTop[1] + (cBottom[1] - cTop[1]) * t;
      rgba[o + 2] = cTop[2] + (cBottom[2] - cTop[2]) * t;
      rgba[o + 3] = (cov / 4) * 255;
    }
  }
  // white glyph, centered, occupying ~60% of the icon
  const glyphSize = Math.round(size * 0.6);
  const glyph = renderGlyph(glyphSize, [255, 255, 255], 4);
  const off = Math.floor((size - glyphSize) / 2);
  for (let y = 0; y < glyphSize; y++) {
    for (let x = 0; x < glyphSize; x++) {
      const go = (y * glyphSize + x) * 4;
      const a = glyph[go + 3] / 255;
      if (a === 0) continue;
      const o = ((y + off) * size + (x + off)) * 4;
      rgba[o] = 255; rgba[o + 1] = 255; rgba[o + 2] = 255;
      rgba[o + 3] = Math.max(rgba[o + 3], glyph[go + 3]);
    }
  }
  return rgba;
}

function writePNG(path, size, rgba) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, encodePNG(size, size, rgba));
  console.log('wrote', path);
}

// menu-bar template icons: black glyph on transparent, 22pt + 44pt @2x
writePNG(join(ROOT, 'App/Resources/MenuBarIconTemplate.png'), 22, renderGlyph(22, [0, 0, 0]));
writePNG(join(ROOT, 'App/Resources/MenuBarIconTemplate@2x.png'), 44, renderGlyph(44, [0, 0, 0]));

// app iconset
const iconset = join(ROOT, 'App/Resources/AppIcon.iconset');
const sizes = [16, 32, 128, 256, 512];
for (const s of sizes) {
  writePNG(join(iconset, `icon_${s}x${s}.png`), s, renderAppIcon(s));
  writePNG(join(iconset, `icon_${s}x${s}@2x.png`), s * 2, renderAppIcon(s * 2));
}
console.log('done');
