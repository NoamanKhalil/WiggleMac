import React from "react";
import { T, bump, frustrationAt, surgeFor, window01 } from "../timeline";
import { DISPLAY, FAINT, GREEN, INK, INK_LINE, MUTED, PAPER, PINK, YELLOW, linear } from "../theme";

/** Lower-third narration, bottom-left, clear of Wiggle's panel. */
export const Caption: React.FC<{ frame: number; start: number; end: number; title: string; sub: string; highlight?: string }> = ({
  frame,
  start,
  end,
  title,
  sub,
  highlight,
}) => {
  const v = window01(frame, start, end, 8, 6);
  if (v <= 0) return null;
  const parts = highlight ? title.split(highlight) : [title];
  return (
    <div style={{ position: "absolute", left: 96, bottom: 96, maxWidth: 1040, opacity: v, transform: `translateY(${(1 - v) * 24}px)` }}>
      <div
        style={{
          display: "flex",
          gap: 26,
          padding: "26px 40px 30px 30px",
          borderRadius: 26,
          background: "rgba(20, 18, 26, 0.88)",
          backdropFilter: "blur(16px)",
          boxShadow: "0 20px 60px rgba(0,0,0,0.35)",
        }}
      >
        <div style={{ width: 8, flex: "none", borderRadius: 8, background: linear(180) }} />
        <div>
          <div style={{ fontFamily: DISPLAY, fontWeight: 700, fontSize: 58, lineHeight: 1.05, letterSpacing: -1, color: PAPER }}>
            {parts.map((part, i) => (
              <React.Fragment key={i}>
                {i > 0 && <span style={{ color: YELLOW }}>{highlight}</span>}
                {part}
              </React.Fragment>
            ))}
          </div>
          <div style={{ fontFamily: DISPLAY, fontWeight: 500, fontSize: 31, lineHeight: 1.3, color: MUTED, marginTop: 10 }}>{sub}</div>
        </div>
      </div>
    </div>
  );
};

// Frames where surge pricing steps up, for a little price pop.
const SURGE_STEPS = (() => {
  const steps: number[] = [];
  let previous = surgeFor(frustrationAt(228));
  for (let f = 229; f < T.clickUnlock; f++) {
    const s = surgeFor(frustrationAt(f));
    if (s !== previous) steps.push(f);
    previous = s;
  }
  return steps;
})();

/** The pitch's satirical meter: how frustrated you are, and what that costs. */
export const FrustrationHUD: React.FC<{ frame: number }> = ({ frame: f }) => {
  const v = window01(f, 228, 760, 10, 10);
  if (v <= 0) return null;
  const index = frustrationAt(f);
  const paid = f >= T.clickUnlock + 3;
  const surge = surgeFor(index);
  const price = paid ? 3.96 : 0.99 * surge;
  const pop = 1 + 0.16 * Math.max(0, ...SURGE_STEPS.map((s) => bump(f, s, 10)), bump(f, T.clickUnlock + 3, 10));
  const pill = paid
    ? { text: "PAID", background: GREEN, color: INK }
    : surge > 1
      ? { text: `${surge}x SURGE`, background: YELLOW, color: INK }
      : { text: "1x", background: INK_LINE, color: MUTED };

  return (
    <div
      style={{
        position: "absolute",
        right: 96,
        bottom: 96,
        width: 430,
        padding: "22px 30px 28px",
        borderRadius: 26,
        background: "rgba(20, 18, 26, 0.9)",
        border: `1px solid ${INK_LINE}`,
        backdropFilter: "blur(16px)",
        boxShadow: "0 20px 60px rgba(0,0,0,0.35)",
        fontFamily: DISPLAY,
        color: PAPER,
        opacity: v,
        transform: `translateY(${(1 - v) * 24}px)`,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span style={{ fontSize: 18, fontWeight: 600, letterSpacing: 3, color: MUTED }}>FRUSTRATION INDEX</span>
        <span style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 16, fontWeight: 700, letterSpacing: 2, color: PINK }}>
          <span style={{ width: 9, height: 9, borderRadius: 5, background: PINK, opacity: 0.35 + 0.65 * Math.abs(Math.cos(f / 9)) }} />
          LIVE
        </span>
      </div>
      <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", marginTop: 8 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
          <span style={{ fontSize: 92, fontWeight: 700, lineHeight: 1, letterSpacing: -2, fontVariantNumeric: "tabular-nums" }}>{Math.round(index)}</span>
          <span style={{ fontSize: 28, fontWeight: 500, color: FAINT }}>/100</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 10 }}>
          <span style={{ fontSize: 48, fontWeight: 700, lineHeight: 1, color: YELLOW, transform: `scale(${pop})`, transformOrigin: "right bottom" }}>${price.toFixed(2)}</span>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: 1.5, padding: "5px 12px", borderRadius: 999, background: pill.background, color: pill.color }}>{pill.text}</span>
        </div>
      </div>
      <div style={{ height: 12, marginTop: 18, borderRadius: 6, background: INK_LINE, overflow: "hidden" }}>
        <div style={{ width: `${index}%`, height: "100%", borderRadius: 6, background: linear() }} />
      </div>
    </div>
  );
};
