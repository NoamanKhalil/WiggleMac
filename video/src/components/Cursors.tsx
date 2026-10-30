import React from "react";
import { clamp01 } from "../timeline";
import { conic } from "../theme";

// ArrowShape from CursorGlow.swift: an 18×27 pointer with its tip at the top-left.
const ARROW = [
  [0, 0],
  [0, 22],
  [5.2, 17.2],
  [8.8, 25.5],
  [12.4, 24],
  [8.9, 15.9],
  [16, 15.9],
];
const POINTS = ARROW.map(([x, y]) => `${x},${y}`).join(" ");
const CLIP = `polygon(${ARROW.map(([x, y]) => `${x}px ${y}px`).join(", ")})`;

/** The ordinary black macOS pointer. The tip sits at (x, y). */
export const SystemCursor: React.FC<{ x: number; y: number; press?: number; opacity?: number }> = ({ x, y, press = 1, opacity = 1 }) => (
  <svg
    width={22}
    height={31}
    viewBox="-2 -2 22 31"
    style={{
      position: "absolute",
      left: x - 2,
      top: y - 2,
      overflow: "visible",
      opacity,
      transform: `scale(${press})`,
      transformOrigin: "2px 2px",
      filter: "drop-shadow(0 1px 1.5px rgba(0,0,0,0.45))",
    }}
  >
    <polygon points={POINTS} fill="#000" stroke="#fff" strokeWidth={1.6} strokeLinejoin="round" />
  </svg>
);

/**
 * Wiggle's multicolor pointer with its soft halo (GlowView in CursorGlow.swift).
 * `appear` follows the app's spring: 0.2× and transparent when hidden, 1× when shown.
 */
export const RainbowCursor: React.FC<{
  x: number;
  y: number;
  angle: number;
  pulse?: number;
  appear?: number;
  press?: number;
  opacity?: number;
}> = ({ x, y, angle, pulse = 1, appear = 1, press = 1, opacity = 1 }) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width: 0,
      height: 0,
      opacity: clamp01(appear) * opacity,
      transform: `scale(${(0.2 + 0.8 * appear) * press})`,
    }}
  >
    <div
      style={{
        position: "absolute",
        left: -22,
        top: -22,
        width: 44,
        height: 44,
        borderRadius: "50%",
        background: conic(angle),
        filter: "blur(12px)",
        opacity: 0.55,
        transform: `scale(${pulse})`,
      }}
    />
    <div style={{ position: "absolute", left: 0, top: 0, filter: "drop-shadow(0 1px 2px rgba(0,0,0,0.35))" }}>
      <div style={{ width: 18, height: 27, background: conic(angle), clipPath: CLIP }} />
      <svg width={20} height={29} viewBox="-1 -1 20 29" style={{ position: "absolute", left: -1, top: -1, overflow: "visible" }}>
        <polygon points={POINTS} fill="none" stroke="#fff" strokeWidth={1.5} strokeLinejoin="round" />
      </svg>
    </div>
  </div>
);
