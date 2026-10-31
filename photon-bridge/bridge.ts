// Passes your iMessages to Wiggle on this Mac, through Photon, and texts back Wiggle's replies.
// Only messages from WIGGLE_ALLOWED_SENDER get through: a text can start a workflow that clicks
// and types on this Mac.
//
//   npm start               iMessage, with the project's credentials in .env
//   npm run terminal        try it by typing here instead, no Photon account needed
//
// Photon 2.0 (Beta) projects, whose IDs start "pho_prj_", use the Beta API with a project API key
// (pho_sk_…): new texts are fetched every two seconds, so no public webhook address is needed.
// Other projects use the Spectrum SDK with the project secret.
//
// Wiggle's Settings → Texting runs the bundled copy (npm run bundle) itself, with WIGGLE_MANAGED=1.

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { Spectrum } from "spectrum-ts";
import { imessage } from "spectrum-ts/providers/imessage";
import { terminal } from "spectrum-ts/providers/terminal";

const inTerminal = process.argv.includes("--terminal");
const managed = process.env.WIGGLE_MANAGED === "1";

// Run by Wiggle: when Wiggle quits or crashes, stdin closes, and the bridge goes too.
if (managed) {
  process.stdin.on("end", () => process.exit(0));
  process.stdin.resume();
}
const allowedSender = (process.env.WIGGLE_ALLOWED_SENDER ?? "").trim();

if (!inTerminal && !allowedSender) {
  console.error("Error: Set WIGGLE_ALLOWED_SENDER in .env to the phone number (or Apple ID email) you'll text from.");
  process.exit(1);
}

/** Phone numbers match on their last 10 digits, so "+1 (555) 123-4567" and "5551234567" agree. */
function isAllowed(senderID: string | undefined): boolean {
  if (inTerminal) return true;
  if (!senderID) return false;
  if (allowedSender.includes("@")) return senderID.toLowerCase() === allowedSender.toLowerCase();
  const digits = (value: string) => value.replace(/\D/g, "").slice(-10);
  return digits(allowedSender).length === 10 && digits(senderID) === digits(allowedSender);
}

type WiggleInfo = { port: number; token: string };

/** Wiggle writes its port and token here while Allow Texting Wiggle is on, and a new token on each start. */
async function wiggleInfo(): Promise<WiggleInfo> {
  const path = join(homedir(), "Library/Application Support/Wiggle/remote.json");
  try {
    return JSON.parse(await readFile(path, "utf8")) as WiggleInfo;
  } catch {
    throw new Error("Texting is off in Wiggle. On your Mac, turn on Allow Texting Wiggle in its menu bar menu.");
  }
}

async function wiggle(method: "GET" | "POST", path: string, body?: unknown): Promise<any> {
  const { port, token } = await wiggleInfo();
  let response: Response;
  try {
    response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new Error("Wiggle isn't running on your Mac.");
  }
  const json = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(json.error ?? `Wiggle answered with HTTP ${response.status}.`);
  return json;
}

/** Texts once a run that a "yes" started is over. */
async function reportWhenDone(space: { send(text: string): Promise<unknown> }, name: string) {
  for (;;) {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    try {
      const status = await wiggle("GET", "/status");
      if (!status.running) break;
    } catch {
      break;
    }
  }
  await space.send(`“${name}” has finished.`);
}

/** Lines starting "Error: " are what Wiggle's Texting settings show when the bridge stops. */
function fail(error: unknown): never {
  const status = (error as { status?: number }).status;
  let reason: string;
  if (beta && (status === 401 || status === 403)) {
    reason = status === 401
      ? "Photon didn't accept the API key. Create one on your project's API keys page at app.beta.photon.codes."
      : "The API key isn't allowed to read and send messages. Give it those permissions on the API keys page.";
  } else if (beta && status === 404) {
    reason = `Photon can't find project ${projectID}. Copy the project ID from app.beta.photon.codes.`;
  } else if (status === 401 || status === 403 || status === 422) {
    reason = `Photon didn't accept the project ID or secret (HTTP ${status}). Check them in your project's Settings at app.photon.codes.`;
  } else {
    reason = `Couldn't connect to Photon: ${error instanceof Error ? error.message : String(error)}`;
  }
  console.error(`Error: ${reason}`);
  process.exit(1);
}

/** Wiggle's reply to one text, and the run it started, if any. */
async function answer(text: string): Promise<{ reply: string; started?: string }> {
  try {
    return await wiggle("POST", "/message", { text });
  } catch (error) {
    return { reply: error instanceof Error ? error.message : String(error) };
  }
}

const projectID = (process.env.PHOTON_PROJECT_ID ?? process.env.SPECTRUM_PROJECT_ID ?? "").trim();
const beta = !inTerminal && projectID.startsWith("pho_prj_");

async function runSpectrum() {
  const app = await Spectrum({
    providers: [inTerminal ? terminal.config() : imessage.config()],
  }).catch(fail);
  console.log(inTerminal ? "Type a message for Wiggle (try “help”)." : `Waiting for texts from ${allowedSender}.`);

  for await (const [space, message] of app.messages) {
    if (message.direction !== "inbound" || message.content.type !== "text") continue;
    if (!isAllowed(message.sender?.id)) {
      console.warn(`Ignored a text from ${message.sender?.id ?? "an unknown sender"}.`);
      continue;
    }
    const text = message.content.text;
    const result = await space.responding(() => answer(text));
    await space.send(result.reply);
    if (result.started) void reportWhenDone(space, result.started);
  }
}

// MARK: Photon 2.0 (Beta)

class PhotonError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

type BetaMessage = {
  id: string;
  createdAt: string;
  content?: { type?: string; text?: string };
  sentBy?: { handle?: string };
  receivedBy?: { id?: string };
  space?: { id?: string };
};

async function runBeta() {
  const apiKey = (process.env.PHOTON_PROJECT_API_KEY ?? process.env.SPECTRUM_PROJECT_SECRET ?? "").trim();
  // PHOTON_API_URL points the bridge at a stand-in for Photon, for testing.
  const base = `${process.env.PHOTON_API_URL ?? "https://api.photon.codes"}/v1/projects/${projectID}`;

  async function photon(method: "GET" | "POST", path: string, body?: unknown): Promise<any> {
    const response = await fetch(base + path, {
      method,
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw new PhotonError(response.status, json.title ?? `HTTP ${response.status}`);
    return json;
  }

  const send = (spaceId: string, senderId: string, text: string) =>
    photon("POST", "/messages", { spaceId, senderId, content: { type: "text", format: "plain", text } });

  // Checks the key and project before waiting.
  await photon("GET", "/messages?pageSize=1&direction=received").catch(fail);
  // Which iMessage line the project has, for the log: no line means no texts.
  for (const path of ["/platforms/imessage", "/platforms/imessage/assignments", "/platforms/resources"]) {
    const result = await photon("GET", path).catch((error) => ({ error: String(error.message ?? error) }));
    console.log(`Photon ${path}: ${JSON.stringify(result).slice(0, 600)}`);
  }
  console.log(`Waiting for texts from ${allowedSender}.`);

  // Texts from before the bridge started are left alone. `createdSince` includes its bound,
  // so texts already handled are remembered by ID.
  let since = new Date().toISOString();
  const handled = new Set<string>();

  for (;;) {
    try {
      const query = new URLSearchParams({
        direction: "received", platform: "imessage", createdSince: since,
        order: "asc", orderBy: "created_at", pageSize: "50",
      });
      const page = await photon("GET", `/messages?${query}`);
      const items = (page.items ?? []) as BetaMessage[];
      if (items.some((item) => !handled.has(item.id))) console.log(`Photon has ${items.length} received text(s) since ${since}.`);
      for (const message of items) {
        if (handled.has(message.id)) continue;
        handled.add(message.id);
        if (Date.parse(message.createdAt) > Date.parse(since)) since = message.createdAt;
        await handle(message);
      }
      if (handled.size > 500) [...handled].slice(0, 400).forEach((id) => handled.delete(id));
    } catch (error) {
      if (error instanceof PhotonError && (error.status === 401 || error.status === 403)) fail(error);
      console.error(`Couldn't check for texts: ${error instanceof Error ? error.message : String(error)}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  async function handle(message: BetaMessage) {
    const from = message.sentBy?.handle ?? "an unknown sender";
    console.log(`Got ${message.id} from ${from} (${message.content?.type ?? "no content"}).`);
    if (message.content?.type !== "text" || !message.content.text) {
      console.log(`Skipped ${message.id}: not text. Fields: ${Object.keys(message).join(", ")}.`);
      return;
    }
    if (!isAllowed(message.sentBy?.handle)) {
      console.warn(`Ignored a text from ${from}.`);
      return;
    }
    const spaceId = message.space?.id;
    const senderId = message.receivedBy?.id; // the line it came in on replies
    if (!spaceId || !senderId) {
      console.log(`Skipped ${message.id}: no space or line to reply on (space ${spaceId}, line ${senderId}).`);
      return;
    }

    void photon("POST", `/messages/${message.id}/read`).catch(() => {});
    const typing = (on: boolean) => photon("POST", `/spaces/${spaceId}/typing`, { senderId, typing: on }).catch(() => {});
    await typing(true);
    const result = await answer(message.content.text);
    await typing(false);
    try {
      await send(spaceId, senderId, result.reply);
      console.log(`Replied to ${message.id}.`);
    } catch (error) {
      console.error(`Couldn't send the reply: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (result.started) void reportWhenDone({ send: (text) => send(spaceId, senderId, text) }, result.started);
  }
}

// Last, so everything above is defined first.
if (beta) {
  await runBeta();
} else {
  await runSpectrum();
}
