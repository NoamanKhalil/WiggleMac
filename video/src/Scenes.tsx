import React from "react";
import { AbsoluteFill, Easing, spring } from "remotion";
import { Caption, FrustrationHUD } from "./components/Overlays";
import { Desktop } from "./components/Desktop";
import { Panel } from "./components/Panel";
import { RainbowCursor, SystemCursor } from "./components/Cursors";
import {
  CAPTIONS,
  FPS,
  T,
  cameraAt,
  clamp01,
  cursorAngle,
  cursorAt,
  cursorPulse,
  desktopState,
  isShaking,
  pressAt,
  ramp,
} from "./timeline";
import { DISPLAY, FAINT, INK, PAPER, YELLOW, linear } from "./theme";

const gradientText: React.CSSProperties = {
  background: linear(),
  WebkitBackgroundClip: "text",
  backgroundClip: "text",
  color: "transparent",
};

const Glow: React.FC = () => (
  <AbsoluteFill
    style={{
      background: [
        "radial-gradient(55% 60% at 88% 12%, rgba(148, 107, 219, 0.28), transparent 70%)",
        "radial-gradient(50% 60% at 6% 100%, rgba(227, 97, 148, 0.22), transparent 70%)",
      ].join(", "),
    }}
  />
);

/** Digits in fixed-width boxes so the count-up doesn't wobble. */
const Counter: React.FC<{ value: number }> = ({ value }) => (
  <div style={{ display: "flex", fontFamily: DISPLAY, fontWeight: 700, fontSize: 170, lineHeight: 1, color: PAPER }}>
    {Math.round(value)
      .toLocaleString("en-US")
      .split("")
      .map((ch, i) => (
        <span key={i} style={{ display: "inline-block", width: ch === "," ? "0.26em" : "0.6em", textAlign: "center" }}>
          {ch}
        </span>
      ))}
  </div>
);

/** Lead with the problem and a number. */
export const ColdOpen: React.FC<{ frame: number }> = ({ frame: f }) => {
  const label = ramp(f, 4, 14, Easing.out(Easing.cubic));
  const count = ramp(f, 8, 58, Easing.out(Easing.cubic));
  const sub = ramp(f, 30, 44, Easing.out(Easing.cubic));
  const punch = spring({ frame: f - 72, fps: FPS, config: { damping: 14, stiffness: 160 } });
  return (
    <AbsoluteFill style={{ background: INK, opacity: 1 - ramp(f, T.coldOpenOut[0], T.coldOpenOut[1]) }}>
      <Glow />
      <div style={{ position: "absolute", left: 160, right: 160, top: 0, bottom: 0, display: "flex", flexDirection: "column", justifyContent: "center" }}>
        <div style={{ fontFamily: DISPLAY, fontWeight: 600, fontSize: 30, letterSpacing: 6, color: YELLOW, opacity: label, marginBottom: 28 }}>THE PROBLEM</div>
        <Counter value={2.3e12 * count} />
        <div
          style={{
            fontFamily: DISPLAY,
            fontWeight: 500,
            fontSize: 54,
            lineHeight: 1.25,
            color: PAPER,
            marginTop: 32,
            maxWidth: 1400,
            opacity: sub,
            transform: `translateY(${(1 - sub) * 20}px)`,
          }}
        >
          times a year, someone shakes their mouse because they're stuck.
        </div>
        <div
          style={{
            fontFamily: DISPLAY,
            fontWeight: 700,
            fontSize: 84,
            lineHeight: 1.05,
            letterSpacing: -1.5,
            color: PAPER,
            marginTop: 72,
            opacity: clamp01(punch),
            transform: `scale(${0.92 + 0.08 * punch})`,
            transformOrigin: "left center",
          }}
        >
          Every single one of them is <span style={gradientText}>free</span>.
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** The screen recording part: the problem, the wiggle, the panel, the paywall, the close. */
export const DesktopStory: React.FC<{ frame: number }> = ({ frame: f }) => {
  const opacity = Math.min(ramp(f, T.desktopIn[0], T.desktopIn[1]), 1 - ramp(f, T.desktopOut[0], T.desktopOut[1]));
  if (opacity <= 0) return null;

  const cam = cameraAt(f);
  const p = cursorAt(f);
  const press = pressAt(f);
  const glowShown = f >= T.open && f < T.close + 6;
  const appear =
    f < T.close
      ? spring({ frame: f - T.open, fps: FPS, config: { mass: 1, stiffness: 322, damping: 21.5 } })
      : 1 - ramp(f, T.close, T.close + 6, Easing.out(Easing.cubic));
  const systemShown = f < T.open || f >= T.close;
  const flash = f < T.flash ? 0 : 0.5 * (1 - ramp(f, T.flash + 2, T.flash + 12, Easing.out(Easing.quad))) * ramp(f, T.flash, T.flash + 2);
  // Cheap motion blur: ghosts at sub-frame offsets while shaking.
  const ghosts = isShaking(f) ? [0.75, 0.5, 0.25] : [];

  return (
    <AbsoluteFill style={{ background: "#0B0A10", opacity }}>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: 1280,
          height: 720,
          transformOrigin: "0 0",
          transform: `translate(960px, 540px) scale(${cam.s}) translate(${-cam.x}px, ${-cam.y}px)`,
        }}
      >
        <Desktop state={desktopState(f)} />
        {flash > 0 && <div style={{ position: "absolute", inset: 0, background: "#fff", opacity: flash }} />}
        <Panel frame={f} />
        {systemShown &&
          ghosts.map((k) => {
            const q = cursorAt(f - k);
            return <SystemCursor key={k} x={q.x} y={q.y} opacity={0.4 * (1 - k)} />;
          })}
        {systemShown && <SystemCursor x={p.x} y={p.y} press={press} />}
        {glowShown &&
          ghosts.map((k) => {
            const q = cursorAt(f - k);
            return <RainbowCursor key={k} x={q.x} y={q.y} angle={cursorAngle(f - k)} appear={appear} opacity={0.35 * (1 - k)} />;
          })}
        {glowShown && <RainbowCursor x={p.x} y={p.y} angle={cursorAngle(f)} pulse={cursorPulse(f)} appear={appear} press={press} />}
      </div>
      {CAPTIONS.map((c) => (
        <Caption key={c.start} frame={f} {...c} />
      ))}
      <FrustrationHUD frame={f} />
    </AbsoluteFill>
  );
};

/** Land on the one-liner. */
export const Ending: React.FC<{ frame: number }> = ({ frame: f }) => {
  const logo = spring({ frame: f - 768, fps: FPS, config: { damping: 14, stiffness: 150 } });
  const line = spring({ frame: f - 790, fps: FPS, config: { damping: 16, stiffness: 110 } });
  const credits = ramp(f, 824, 840, Easing.out(Easing.cubic));
  return (
    <AbsoluteFill style={{ background: INK, opacity: ramp(f, T.endStart, T.endStart + 16), alignItems: "center", justifyContent: "center" }}>
      <Glow />
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 30, opacity: clamp01(logo), transform: `translateY(${(1 - logo) * 24}px)` }}>
          <div style={{ position: "relative", width: 54, height: 81 }}>
            <div style={{ position: "absolute", left: 0, top: 0, transform: "scale(3)", transformOrigin: "0 0" }}>
              <RainbowCursor x={0} y={0} angle={cursorAngle(f)} />
            </div>
          </div>
          <span style={{ fontFamily: DISPLAY, fontWeight: 700, fontSize: 104, lineHeight: 1, letterSpacing: -2, ...gradientText }}>Wiggle</span>
        </div>
        <div
          style={{
            marginTop: 76,
            maxWidth: 1500,
            fontFamily: DISPLAY,
            fontWeight: 700,
            fontSize: 124,
            lineHeight: 1.02,
            letterSpacing: -3,
            color: PAPER,
            textAlign: "center",
            textWrap: "balance",
            opacity: clamp01(line),
            transform: `translateY(${(1 - line) * 40}px) scale(${0.94 + 0.06 * line})`,
          }}
        >
          You were going to wiggle anyway.
        </div>
        <div style={{ marginTop: 72, fontFamily: DISPLAY, fontWeight: 500, fontSize: 30, letterSpacing: 1, color: FAINT, opacity: credits }}>
          Made by Vicki, Noaman &amp; Najia
        </div>
      </div>
    </AbsoluteFill>
  );
};
