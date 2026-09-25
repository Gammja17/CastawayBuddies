// 웹판 방 코드 멀티 시험: 헤드리스 크롬 넷 (방장 / 손님 둘 / 틀린 코드)
//   1) 웹으로 내보내기: godot --headless --path . --export-release "Web" <폴더>/index.html
//   2) 그 폴더에서: python -m http.server 8766 --bind 127.0.0.1
//   3) node tools/web_mp_test.mjs <화면 저장 폴더>
// 중개 서버(0.peerjs.com)에 실제로 붙으니 인터넷이 필요하다.
import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";

const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const BASE = "http://127.0.0.1:8766/index.html";
const OUT = process.argv[2] || ".";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function launch(name, port, url) {
  const dir = `${process.env.TEMP || "."}/cb_chrome_${name}`;
  mkdirSync(dir, { recursive: true });
  const proc = spawn(CHROME, [
    "--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${dir}`, "--window-size=1280,720",
    "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--no-first-run",
    "--autoplay-policy=no-user-gesture-required", url,
  ], { stdio: "ignore" });
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(500);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find((t) => t.type === "page");
    } catch {}
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => (ws.onopen = r));
  let id = 0;
  const pending = new Map();
  const logs = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
    if (m.method === "Runtime.consoleAPICalled") {
      const text = m.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
      logs.push(text);
      if (text.startsWith("[") || /error/i.test(text)) console.log(`  (${name}) ${text.slice(0, 200)}`);
    }
    if (m.method === "Runtime.exceptionThrown") console.log(`  (${name}) 예외: ${JSON.stringify(m.params.exceptionDetails).slice(0, 300)}`);
  };
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await send("Runtime.enable");
  await send("Page.enable");
  const shot = async (file) => {
    const res = await send("Page.captureScreenshot", { format: "png" });
    writeFileSync(`${OUT}/${file}`, Buffer.from(res.data, "base64"));
  };
  const waitLog = async (re, secs) => {
    for (let i = 0; i < secs * 2; i++) {
      const hit = logs.find((l) => re.test(l));
      if (hit) return hit;
      await sleep(500);
    }
    return null;
  };
  return { proc, send, shot, waitLog, logs };
}

const host = await launch("host", 9301, `${BASE}?autostart=host`);
const codeLine = await host.waitLog(/방 코드\]/, 120);
const code = codeLine.split("]")[1].trim();
console.log("방 코드:", code);
const g1 = await launch("guest", 9302, `${BASE}?join=${code}&go=1`);
const g2 = await launch("guest2", 9303, `${BASE}?join=${code.toLowerCase()}&go=1`);
const bad = await launch("bad", 9304, `${BASE}?join=QQQQ7&go=1`);
const j1 = await g1.waitLog(/섬 받음/, 120);
const j2 = await g2.waitLog(/섬 받음/, 120);
await sleep(8000);
console.log("손님1:", j1, "/ 손님2:", j2, "/ 방장 들어옴:", host.logs.filter((l) => l.includes("들어옴")));
await host.shot("webmp3_host.png");
await g2.shot("webmp3_guest2.png");
await bad.shot("webmp3_bad.png");
for (const b of [host, g1, g2, bad]) b.proc.kill();
process.exit(j1 && j2 ? 0 : 2);
