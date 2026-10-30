import { Easing, interpolate } from "remotion";

export const FPS = 30;
export const DURATION = 870;

export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** 0 before `start`, 1 after `end`, eased in between. */
export const ramp = (f: number, start: number, end: number, easing = Easing.inOut(Easing.cubic)) =>
  interpolate(f, [start, end], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });

/** 1 inside [start, end], fading in and out at the edges. */
export const window01 = (f: number, start: number, end: number, fadeIn = 8, fadeOut = 6) =>
  Math.min(ramp(f, start, start + fadeIn, Easing.out(Easing.cubic)), 1 - ramp(f, end - fadeOut, end, Easing.in(Easing.cubic)));

/** A quick 0 → 1 → 0 bump starting at `at`. */
export const bump = (f: number, at: number, length = 8) => {
  const t = (f - at) / length;
  return t < 0 || t > 1 ? 0 : Math.sin(Math.PI * t);
};

// Story beats, in frames at 30 fps.
export const T = {
  coldOpenOut: [120, 135] as const,
  desktopIn: [118, 135] as const,
  selectCell: 200,
  open: 306, // fifth counted reversal of the third wiggle
  camIn: [306, 350] as const,
  clickScreenshot: 388,
  chatStage: 390,
  capture: [392, 424] as const,
  flash: 402,
  type: [432, 480] as const,
  submit: 486,
  stream: [498, 560] as const,
  paywall: 562,
  clickUnlock: 630,
  reveal: [634, 650] as const,
  close: 682, // fifth counted reversal of the closing wiggle
  camOut: [690, 740] as const,
  desktopOut: [758, 774] as const,
  endStart: 758,
};

// World = the Mac's screen in points. The camera scales it into the 1920×1080 frame.
export const WORLD = { width: 1280, height: 720 };
export const WIN = { x: 60, y: 50, width: 880, height: 560 };
export const GRID = { left: 20, top: 96, header: 22, row: 24, rowNumber: 34, columns: [168, 96, 96, 96, 120] };

/** Where the pointer rests on cell E7 when the user gets stuck. */
export const STUCK = { x: 594, y: 322 };
/** Wiggle's card sits 14 pt (gap) + 8 pt (card padding) below-right of the pointer, as in PromptPanelController. */
export const CARD = { x: STUCK.x + 22, y: STUCK.y + 22 };
export const CHOOSER_TILES = [
  { id: "chat", title: "Chat", icon: "bubble", x: 4, width: 64 },
  { id: "screenshot", title: "Screenshot", icon: "viewfinder", x: 70, width: 104 },
  { id: "voice", title: "Voice", icon: "micFill", x: 176, width: 68 },
] as const;
export const UNLOCK_BUTTON = { x: CARD.x + 88, y: CARD.y + 114 };

const SCREENSHOT_TILE = { x: CARD.x + 70 + 52, y: CARD.y + 17 };

// Pointer path: [frame, x, y]. Eased between points.
const PATH: [number, number, number][] = [
  [118, 470, 470],
  [150, 470, 470],
  [184, 556, 356],
  [198, STUCK.x, STUCK.y],
  [356, STUCK.x, STUCK.y],
  [386, SCREENSHOT_TILE.x, SCREENSHOT_TILE.y],
  [394, SCREENSHOT_TILE.x, SCREENSHOT_TILE.y],
  [418, 588, 318],
  [596, 588, 318],
  [626, UNLOCK_BUTTON.x, UNLOCK_BUTTON.y],
  [640, UNLOCK_BUTTON.x, UNLOCK_BUTTON.y],
  [660, 990, 470],
  [694, 990, 470],
  [740, 880, 430],
];

/** Back-and-forth shakes. Peaks (direction reversals) land every half period. */
export const WIGGLES = [
  { start: 232, end: 250, amp: 16, period: 12 },
  { start: 262, end: 284, amp: 28, period: 10 },
  { start: 288, end: 312, amp: 44, period: 8 },
  { start: 664, end: 694, amp: 42, period: 8 },
];

export const reversalsOf = (w: (typeof WIGGLES)[number]) => {
  const peaks: number[] = [];
  for (let t = w.start + w.period / 4; t < w.end - 1; t += w.period / 2) peaks.push(t);
  return peaks;
};

export const cursorAt = (f: number) => {
  let x = PATH[0][1];
  let y = PATH[0][2];
  for (let i = 0; i < PATH.length - 1; i++) {
    const [f0, x0, y0] = PATH[i];
    const [f1, x1, y1] = PATH[i + 1];
    if (f >= f1) {
      x = x1;
      y = y1;
      continue;
    }
    if (f >= f0) {
      const t = ramp(f, f0, f1, Easing.inOut(Easing.sin));
      x = lerp(x0, x1, t);
      y = lerp(y0, y1, t);
    }
    break;
  }
  for (const w of WIGGLES) {
    if (f < w.start || f > w.end) continue;
    const envelope = clamp01(Math.min((f - w.start) / 3, (w.end - f) / 3));
    const phase = (2 * Math.PI * (f - w.start)) / w.period;
    x += w.amp * envelope * Math.sin(phase);
    y += 0.2 * w.amp * envelope * Math.sin(2 * phase + 1);
  }
  return { x, y };
};

export const isShaking = (f: number) => WIGGLES.some((w) => f >= w.start && f <= w.end);

const CLICKS = [T.selectCell, T.clickScreenshot, T.clickUnlock];
/** Pointer scale while pressing. */
export const pressAt = (f: number) => 1 - 0.14 * Math.max(...CLICKS.map((c) => bump(f, c, 6)));

// Busy = capturing or generating: the cursor spins faster and the card border spins.
const BUSY: [number, number][] = [
  [T.capture[0], T.capture[1]],
  [T.submit, T.paywall],
];
export const isBusy = (f: number) => BUSY.some(([a, b]) => f >= a && f < b);
const busyFramesBefore = (f: number) => BUSY.reduce((sum, [a, b]) => sum + Math.max(0, Math.min(f, b) - a), 0);
/** 180°/s idle, 540°/s busy, as in CursorGlow; integrated so the speed change doesn't jump. */
export const cursorAngle = (f: number) => 6 * f + 12 * busyFramesBefore(f);
/** The card border spins at 240°/s, only while busy. */
export const borderAngle = (f: number) => 8 * busyFramesBefore(f);
export const cursorPulse = (f: number) => (isBusy(f) ? 1 + 0.12 * Math.sin((f / FPS) * 6) : 1);

// Camera: wide shot of the whole screen, then a close-up on the cursor and panel.
const WIDE = { x: 640, y: 360, s: 1.5 };
const CLOSE = { x: STUCK.x + 164, y: STUCK.y + 141, s: 2.2 };
export const cameraAt = (f: number) => {
  const t = Math.min(ramp(f, T.camIn[0], T.camIn[1]), 1 - ramp(f, T.camOut[0], T.camOut[1]));
  const s = lerp(WIDE.s, CLOSE.s, t);
  const halfW = 960 / s;
  const halfH = 540 / s;
  return {
    s,
    x: Math.min(Math.max(lerp(WIDE.x, CLOSE.x, t), halfW), WORLD.width - halfW),
    y: Math.min(Math.max(lerp(WIDE.y, CLOSE.y, t), halfH), WORLD.height - halfH),
  };
};

// Frustration Index: climbs with every counted reversal, drains once the user has paid.
const SHAKE_REVERSALS = WIGGLES.slice(0, 3).flatMap(reversalsOf);
const CLOSE_REVERSALS = reversalsOf(WIGGLES[3]);
export const frustrationAt = (f: number) => {
  let value = 8;
  const step = (87 - 8) / 12;
  for (const r of SHAKE_REVERSALS) value += step * ramp(f, r, r + 3, Easing.out(Easing.cubic));
  value = Math.min(value, 87);
  value *= 1 - ramp(f, T.clickUnlock + 4, T.clickUnlock + 26);
  for (const r of CLOSE_REVERSALS) value += 5 * ramp(f, r, r + 3, Easing.out(Easing.cubic));
  return Math.min(100, value);
};
export const surgeFor = (index: number) => (index >= 80 ? 4 : index >= 50 ? 2 : 1);

// The spreadsheet: Total cells E2–E8 break in a domino at the start and get fixed at the end.
export type RowState = { broken: boolean; flash: number; fixFlash: number };
export type DesktopState = {
  rows: RowState[];
  selected: boolean;
  formula: "empty" | "broken" | "fixed";
  clock: string;
  notify: { slide: number; body: string; urgent: boolean; bump: number };
};

export const desktopState = (f: number): DesktopState => ({
  rows: Array.from({ length: 7 }, (_, i) => {
    const breakAt = 150 + i * 5;
    const fixAt = 708 + i * 4;
    const broken = f >= breakAt && f < fixAt;
    return {
      broken,
      flash: broken ? 1 - ramp(f, breakAt, breakAt + 12, Easing.out(Easing.quad)) : 0,
      fixFlash: f >= fixAt ? 1 - ramp(f, fixAt, fixAt + 16, Easing.out(Easing.quad)) : 0,
    };
  }),
  selected: f >= T.selectCell,
  formula: f < T.selectCell ? "empty" : f < 728 ? "broken" : "fixed",
  clock: f < 256 ? "4:40 PM" : f < 292 ? "4:55 PM" : "4:59 PM",
  notify: {
    slide: Math.min(ramp(f, 156, 172, Easing.out(Easing.back(1.4))), 1 - ramp(f, 704, 720)),
    body: f < 256 ? "in 20 minutes" : f < 292 ? "in 5 minutes" : "in 1 minute",
    urgent: f >= 292,
    bump: Math.max(bump(f, 256, 10), bump(f, 292, 10)),
  },
});

/** What the screenshot captured: Wiggle's own windows and the pointer are left out. */
export const CAPTURED = desktopState(T.flash);

export const CAPTIONS: { start: number; end: number; title: string; sub: string; highlight?: string }[] = [
  { start: 150, end: 226, title: "You're stuck.", sub: "Deadline in 20 minutes. Everything says #REF!" },
  { start: 230, end: 304, title: "So you shake your mouse.", sub: "Harder. Faster. We're measuring." },
  { start: 310, end: 388, title: "Wiggle appears at your cursor.", sub: "Pick Chat, Screenshot or Voice." },
  { start: 392, end: 484, title: "It sees your whole screen.", sub: "Just for context. Probably." },
  { start: 490, end: 560, title: "Help arrives instantly.", sub: "Right where you're stuck." },
  { start: 564, end: 650, title: "The fix is $3.96.", sub: "4x deadline surge. Your cursor will be returned after payment.", highlight: "$3.96" },
  { start: 656, end: 756, title: "Shake again to close.", sub: "See you in about 4 hours." },
];
