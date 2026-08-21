// Tiny dependency-free Chrome DevTools driver for black-box Web input tests.
// It talks only to the browser: keyboard/mouse input, page title, and screenshots.

import fs from "node:fs";

const [, , command = "capture", code = "", key = "", durationText = "0", output = ""] = process.argv;
const duration = Number(durationText) || 0;
const cdpPort = process.env.CDP_PORT || "9223";
const endpoint = `http://127.0.0.1:${cdpPort}/json/list`;

const pages = await fetch(endpoint).then((response) => response.json());
const page = pages.find((candidate) => candidate.type === "page" && candidate.url.includes("127.0.0.1:8765"));
if (!page) throw new Error("Godot Web page is not open on the Chrome debugging port");

const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});

let nextId = 1;
const pending = new Map();
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result ?? {});
  }
});

function send(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

await send("Page.enable");
await send("Runtime.enable");

if (command === "focus") {
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: 640, y: 360, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 640, y: 360, button: "left", clickCount: 1 });
} else if (command === "down" || command === "up") {
  const virtualKey = key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0;
  await send("Input.dispatchKeyEvent", { type: command === "down" ? "keyDown" : "keyUp", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
} else if (command === "hold" || command === "tap" || command === "combo") {
  const virtualKey = key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0;
  const modifiers = command === "combo" ? (durationText === "ctrl" ? 2 : durationText === "shift" ? 8 : durationText === "ctrl+shift" ? 10 : 0) : 0;
  await send("Input.dispatchKeyEvent", { type: "keyDown", code, key, modifiers, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
  await wait(command === "hold" ? duration : 80);
  await send("Input.dispatchKeyEvent", { type: "keyUp", code, key, modifiers, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
} else if (command === "jumpwalk") {
  const virtualKey = key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0;
  const jumpVirtualKey = 87;
  const startedAt = Date.now();
  await send("Input.dispatchKeyEvent", { type: "keyDown", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
  while (Date.now() - startedAt < duration) {
    await send("Input.dispatchKeyEvent", { type: "keyDown", code: "KeyW", key: "w", windowsVirtualKeyCode: jumpVirtualKey, nativeVirtualKeyCode: jumpVirtualKey });
    await wait(80);
    await send("Input.dispatchKeyEvent", { type: "keyUp", code: "KeyW", key: "w", windowsVirtualKeyCode: jumpVirtualKey, nativeVirtualKeyCode: jumpVirtualKey });
    await wait(Math.min(420, Math.max(0, duration - (Date.now() - startedAt))));
  }
  await send("Input.dispatchKeyEvent", { type: "keyUp", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
} else if (command === "jumpdir") {
  const virtualKey = key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0;
  const jumpVirtualKey = 87;
  await send("Input.dispatchKeyEvent", { type: "keyDown", code: "KeyW", key: "w", windowsVirtualKeyCode: jumpVirtualKey, nativeVirtualKeyCode: jumpVirtualKey });
  await wait(55);
  await send("Input.dispatchKeyEvent", { type: "keyDown", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
  await wait(Math.max(duration, 80));
  await send("Input.dispatchKeyEvent", { type: "keyUp", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
  await send("Input.dispatchKeyEvent", { type: "keyUp", code: "KeyW", key: "w", windowsVirtualKeyCode: jumpVirtualKey, nativeVirtualKeyCode: jumpVirtualKey });
} else if (command === "arc") {
  const virtualKey = key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0;
  const jumpVirtualKey = 87;
  await send("Input.dispatchKeyEvent", { type: "keyDown", code: "KeyW", key: "w", windowsVirtualKeyCode: jumpVirtualKey, nativeVirtualKeyCode: jumpVirtualKey });
  await wait(400);
  await send("Input.dispatchKeyEvent", { type: "keyUp", code: "KeyW", key: "w", windowsVirtualKeyCode: jumpVirtualKey, nativeVirtualKeyCode: jumpVirtualKey });
  await send("Input.dispatchKeyEvent", { type: "keyDown", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
  await wait(Math.max(duration, 80));
  await send("Input.dispatchKeyEvent", { type: "keyUp", code, key, windowsVirtualKeyCode: virtualKey, nativeVirtualKeyCode: virtualKey });
} else if (command === "sequence") {
  const keyInfo = (name) => {
    const upper = name.toUpperCase();
    if (upper === "SPACE") return { code: "Space", key: " ", vk: 32 };
    if (/^[A-Z]$/.test(upper)) return { code: `Key${upper}`, key: upper.toLowerCase(), vk: upper.charCodeAt(0) };
    if (/^[1-5]$/.test(upper)) return { code: `Digit${upper}`, key: upper, vk: upper.charCodeAt(0) };
    throw new Error(`Unknown sequence key: ${name}`);
  };
  const dispatch = async (type, name, modifiers = 0) => {
    const info = keyInfo(name);
    await send("Input.dispatchKeyEvent", { type, code: info.code, key: info.key, modifiers, windowsVirtualKeyCode: info.vk, nativeVirtualKeyCode: info.vk });
  };
  for (const rawStep of code.split(",")) {
    const [rawChord, rawMilliseconds = "80"] = rawStep.trim().split(":");
    const milliseconds = Math.max(Number(rawMilliseconds) || 0, 0);
    const chord = rawChord.trim();
    if (chord.toLowerCase() === "reload") {
      await send("Page.reload", { ignoreCache: true });
      await wait(Math.max(milliseconds, 3000));
      continue;
    }
    if (chord.toLowerCase() === "wait") {
      await wait(milliseconds);
      continue;
    }
    const parts = chord.split("+").map((part) => part.trim()).filter(Boolean);
    let modifiers = 0;
    const keys = [];
    for (const part of parts) {
      if (part.toLowerCase() === "shift") modifiers |= 8;
      else if (part.toLowerCase() === "ctrl") modifiers |= 2;
      else keys.push(part);
    }
    for (const name of keys) await dispatch("keyDown", name, modifiers);
    await wait(Math.max(milliseconds, 45));
    for (const name of keys.reverse()) await dispatch("keyUp", name, modifiers);
  }
} else if (command === "wait") {
  await wait(duration);
} else if (command === "reload") {
  await send("Page.reload", { ignoreCache: true });
  await wait(Math.max(duration, 3000));
}

if (output) {
  const screenshot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
  fs.writeFileSync(output, Buffer.from(screenshot.data, "base64"));
}

const titleResult = await send("Runtime.evaluate", { expression: "document.title", returnByValue: true });
process.stdout.write(JSON.stringify({ command, title: titleResult.result.value, screenshot: output || null }));
socket.close();
