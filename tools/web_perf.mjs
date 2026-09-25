// 웹판 프레임 재기: 헤드리스 크롬(그래픽카드 사용)으로 혼자 하기를 켜서 가만히 / 걸으며 FPS 를 잰다
//   1) 웹으로 내보내기 → 그 폴더에서 python -m http.server 8766 --bind 127.0.0.1
//   2) node tools/web_perf.mjs [주소]
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";

const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const URL = (process.argv[2] || "http://127.0.0.1:8766/index.html") + "?autostart=solo";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dir = `${process.env.TEMP || "."}/cb_chrome_perf`;
mkdirSync(dir, { recursive: true });
const proc = spawn(CHROME, ["--headless=new", "--remote-debugging-port=9311", `--user-data-dir=${dir}`, "--window-size=1280,720",
  "--use-angle=d3d11", "--enable-gpu", "--ignore-gpu-blocklist", "--no-first-run", "--autoplay-policy=no-user-gesture-required", URL], { stdio: "ignore" });
let target = null;
for (let i = 0; i < 60 && !target; i++) {
  await sleep(500);
  try { target = (await (await fetch("http://127.0.0.1:9311/json/list")).json()).find((t) => t.type === "page"); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0;
const pending = new Map();
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJs = async (expr) => (await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true })).result.value;

console.log("그래픽:", await evalJs(`(() => { const gl = document.createElement("canvas").getContext("webgl2"); const e = gl.getExtension("WEBGL_debug_renderer_info"); return gl.getParameter(e.UNMASKED_RENDERER_WEBGL); })()`));
await sleep(45000);   // 불러오기 + 새 게임 시작 + 섬 소개 연출이 끝날 때까지
const measure = (secs) => evalJs(`new Promise((res) => {
  const d = []; let last = performance.now(); const end = last + ${secs} * 1000;
  function f(t) { d.push(t - last); last = t; if (t < end) requestAnimationFrame(f); else {
    const s = [...d].sort((a, b) => a - b); const avg = d.reduce((a, b) => a + b, 0) / d.length;
    res({ fps: +(1000 / avg).toFixed(1), p50: +s[s.length >> 1].toFixed(1), p95: +s[Math.floor(s.length * 0.95)].toFixed(1), max: +s[s.length - 1].toFixed(1),
      over33: d.filter((x) => x > 33.4).length, over50: d.filter((x) => x > 50).length, frames: d.length }); } }
  requestAnimationFrame(f); })`);
console.log("가만히:", JSON.stringify(await measure(8)));
// 걷기 (캔버스에 키를 직접 넣는다)
const key = (type, k, code) => evalJs(`document.querySelector("canvas").dispatchEvent(new KeyboardEvent("${type}", {key: "${k}", code: "${code}", bubbles: true}))`);
await key("keydown", "d", "KeyD");
await key("keydown", "w", "KeyW");
console.log("걸으며:", JSON.stringify(await measure(8)));
await key("keyup", "w", "KeyW");
await key("keyup", "d", "KeyD");
proc.kill();
process.exit(0);
