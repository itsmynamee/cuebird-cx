#!/usr/bin/env node

import { mkdtempSync, rmSync, writeFileSync, copyFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const docs = new URL(".", import.meta.url).pathname;
const output = join(docs, "demo.gif");
const work = mkdtempSync(join(tmpdir(), "cuebird-demo-"));

const run = (command, args) => execFileSync(command, args, { stdio: "inherit" });
const original = execFileSync("git", ["show", "HEAD:docs/demo.gif"]);
const originalGif = join(work, "original.gif");
writeFileSync(originalGif, original);

try {
  run("magick", [originalGif, "-coalesce", join(work, "original-%02d.png")]);

  for (let frame = 0; frame < 39; frame += 1) {
    copyFileSync(join(work, `original-${String(frame).padStart(2, "0")}.png`), join(work, `frame-${String(frame).padStart(2, "0")}.png`));
  }

  const states = [
    { y: 500, opacity: 0, message: 0 },
    { y: 360, opacity: 0.18, message: 0 },
    { y: 300, opacity: 0.38, message: 0 },
    { y: 250, opacity: 0.62, message: 0 },
    { y: 220, opacity: 0.82, message: 0 },
    { y: 204, opacity: 1, message: 0 },
    { y: 202, opacity: 1, message: 0 },
    { y: 202, opacity: 1, message: 0.25 },
    { y: 202, opacity: 1, message: 0.55 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
    { y: 202, opacity: 1, message: 1 },
  ];

  for (const [offset, state] of states.entries()) {
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
  <g opacity="${state.message}">
    <text x="400" y="423" text-anchor="middle" font-family="Helvetica Neue, Arial, sans-serif" font-size="14" fill="#a7a8b0">Mention it once.</text>
    <text x="400" y="454" text-anchor="middle" font-family="Helvetica Neue, Arial, sans-serif" font-size="21" font-weight="700" fill="#ffb327">Never miss what matters.</text>
  </g>
</svg>`;
    const svgPath = join(work, `tail-${offset}.svg`);
    writeFileSync(svgPath, svg);
    run("magick", [svgPath, join(work, `frame-${String(offset + 39).padStart(2, "0")}.png`)]);
  }

  const input = [];
  for (let frame = 0; frame < 58; frame += 1) {
    input.push("-dispose", "Background", "-delay", frame < 39 ? "10" : frame === 57 ? "290" : "10", join(work, `frame-${String(frame).padStart(2, "0")}.png`));
  }
  run("magick", [...input, "-loop", "0", output]);
} finally {
  rmSync(work, { recursive: true, force: true });
}
