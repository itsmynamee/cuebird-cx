#!/usr/bin/env node

import { mkdtempSync, rmSync, writeFileSync, copyFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const docs = new URL(".", import.meta.url).pathname;
const output = join(docs, "demo.gif");
const work = mkdtempSync(join(tmpdir(), "cuebird-demo-"));
const delays = [
  20, 20, 20, 20, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
  50, 20, 20, 20, 60, 40, 120, 10, 10, 50, 40, 220,
];

const run = (command, args) => execFileSync(command, args, { stdio: "inherit" });
const original = execFileSync("git", ["show", "HEAD:docs/demo.gif"]);
const originalGif = join(work, "original.gif");
writeFileSync(originalGif, original);

try {
  run("magick", [originalGif, "-coalesce", join(work, "original-%02d.png")]);

  for (let frame = 0; frame < 34; frame += 1) {
    copyFileSync(join(work, `original-${String(frame).padStart(2, "0")}.png`), join(work, `frame-${String(frame).padStart(2, "0")}.png`));
  }

  let frame = 34;
  for (const opacity of [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0]) {
    run("magick", [
      join(work, "original-33.png"),
      "-channel", "RGB",
      "-evaluate", "Multiply", String(opacity),
      "+channel",
      join(work, `frame-${frame}.png`),
    ]);
    delays.push(5);
    frame += 1;
  }

  const states = [
    { y: 500, opacity: 0, message: false, delay: 50 },
    ...Array.from({ length: 12 }, (_, index) => {
      const progress = (index + 1) / 12;
      const eased = 1 - (1 - progress) ** 3;
      return { y: Math.round(500 + (202 - 500) * eased), opacity: eased, message: false, delay: 5 };
    }),
    { y: 202, opacity: 1, message: false, delay: 50 },
    { y: 202, opacity: 1, message: true, delay: 430 },
  ];

  for (const state of states) {
    const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="800" height="500" viewBox="0 0 800 500">
  <defs>
    <pattern id="dots" width="4" height="4" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r="0.45" fill="#15151a"/></pattern>
    <linearGradient id="card" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#37383f"/><stop offset="1" stop-color="#2e2f35"/></linearGradient>
  </defs>
  <rect width="800" height="500" fill="#060608"/>
  <rect width="800" height="500" fill="url(#dots)"/>
  <g transform="translate(0 ${state.y})" opacity="${state.opacity}">
    <rect x="100" y="0" width="600" height="96" rx="18" fill="#2e2f35"/>
    <rect x="116" y="18" width="52" height="52" rx="13" fill="#fafafa"/>
    <circle cx="132" cy="34" r="4" fill="#ff9500"/><rect x="140" y="31" width="17" height="6" rx="3" fill="#c3c6ce"/>
    <circle cx="132" cy="48" r="4" fill="#0a84ff"/><rect x="140" y="45" width="17" height="6" rx="3" fill="#c3c6ce"/>
    <circle cx="132" cy="62" r="4" fill="#ff375f"/><rect x="140" y="59" width="17" height="6" rx="3" fill="#c3c6ce"/>
    <text x="184" y="29" font-family="Helvetica Neue, Arial, sans-serif" font-size="11" fill="#c5c6cc">REMINDERS</text>
    <text x="680" y="29" text-anchor="end" font-family="Helvetica Neue, Arial, sans-serif" font-size="11" fill="#c5c6cc">now</text>
    <text x="184" y="59" font-family="Helvetica Neue, Arial, sans-serif" font-size="20" font-weight="700" fill="#ffffff">Ship the feature</text>
    <text x="184" y="81" font-family="Helvetica Neue, Arial, sans-serif" font-size="14" fill="#c5c6cc">Set two weeks ago, in Codex</text>
  </g>
  ${state.message ? `<g>
    <text x="400" y="423" text-anchor="middle" font-family="Helvetica Neue, Arial, sans-serif" font-size="14" fill="#a7a8b0">Mention it once.</text>
    <text x="400" y="454" text-anchor="middle" font-family="Helvetica Neue, Arial, sans-serif" font-size="21" font-weight="700" fill="#ffb327">Never miss what matters.</text>
  </g>` : ""}
</svg>`;
    const svgPath = join(work, `tail-${frame}.svg`);
    writeFileSync(svgPath, svg);
    run("magick", [svgPath, join(work, `frame-${frame}.png`)]);
    delays.push(state.delay);
    frame += 1;
  }

  const input = [];
  for (let index = 0; index < delays.length; index += 1) {
    input.push("-dispose", "Background", "-delay", String(delays[index]), join(work, `frame-${String(index).padStart(2, "0")}.png`));
  }
  run("magick", [...input, "-loop", "0", output]);
} finally {
  rmSync(work, { recursive: true, force: true });
}
