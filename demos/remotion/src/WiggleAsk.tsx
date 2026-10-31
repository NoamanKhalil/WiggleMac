import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";

export const FPS = 30;
export const DURATION = 420;

const ink = "#14121A";
const paper = "#F3EFE6";
const muted = "#B9B4C4";
const gold = "#8A5A00";

const clamp = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

const choices = [
  { key: "C", label: "Chat", line: "Ask about whatever is on screen.", at: 150 },
  { key: "S", label: "Screenshot", line: "You choose the screenshot.", at: 210 },
  { key: "V", label: "Voice", line: "Ask out loud. It does not stay on.", at: 270 },
  { key: "W", label: "Workflow", line: "Replay the clicks and typing you saved.", at: 330, ring: true },
] as const;

export const WiggleAsk: React.FC = () => {
  const frame = useCurrentFrame();
  const shake =
    frame < 70 || frame > 130
      ? 0
      : Math.sin(((frame - 70) / 8) * Math.PI) * interpolate(frame, [70, 110, 130], [0, 70, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
  const rainbow = clamp(frame, 118, 136);
  const pop = clamp(frame, 140, 162);
  const active = [...choices].reverse().find((choice) => frame >= choice.at) ?? null;
  const caption =
    frame < 70
      ? "You are stuck on something already on screen."
      : frame < 140
        ? "Shake the pointer. Five quick strokes."
        : frame < 330
          ? "Wiggle opens at the cursor."
          : "Chat, Screenshot, Voice, or Workflow.";

  return (
    <AbsoluteFill style={{ background: ink, color: paper, fontFamily: "Inter, sans-serif" }}>
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 12,
          background: "linear-gradient(90deg,#4285F5,#946BDB,#E36194,#ED4D3D,#FABD1A,#38B366)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 140,
          right: 140,
          top: 150,
          bottom: 210,
          borderRadius: 28,
          background: "#1F1C27",
          boxShadow: "inset 0 0 0 1px #2E2A38",
          overflow: "hidden",
        }}
      >
        <div style={{ position: "absolute", left: 72, top: 64, right: 1000 }}>
          <p style={{ margin: "0 0 28px", fontFamily: '"Space Grotesk", sans-serif', fontSize: 28, letterSpacing: "0.08em", textTransform: "uppercase", color: muted }}>
            On screen
          </p>
          <p style={{ margin: "0 0 18px", fontSize: 42, lineHeight: 1.35 }}>The page you were already reading.</p>
          <p style={{ margin: 0, fontSize: 42, lineHeight: 1.35, color: "#8A8696" }}>You do not have to go find a chat window.</p>
        </div>
        <svg
          viewBox="0 0 24 32"
          width="48"
          height="64"
          style={{ position: "absolute", left: 780 + shake, top: 280 }}
          aria-hidden="true"
        >
          <defs>
            <linearGradient id="cursor-g" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stopColor="#4285F5" />
              <stop offset="0.35" stopColor="#E36194" />
              <stop offset="0.7" stopColor="#FABD1A" />
              <stop offset="1" stopColor="#38B366" />
            </linearGradient>
          </defs>
          <path
            d="M2 2v22l5.2-4.8 3.6 8.3 3.6-1.5-3.5-8.1H18z"
            fill={rainbow > 0.5 ? "url(#cursor-g)" : paper}
            stroke={rainbow > 0.5 ? "#fff" : ink}
            strokeWidth="1.6"
            strokeLinejoin="round"
          />
        </svg>
        <div
          style={{
            position: "absolute",
            left: 680,
            top: 150,
            width: 760,
            padding: 28,
            borderRadius: 28,
            background: "#fffdf8",
            color: ink,
            boxShadow: "0 24px 60px rgba(0,0,0,.35)",
            opacity: pop,
            transform: `translateY(${(1 - pop) * 16}px)`,
          }}
        >
          <p style={{ margin: 0, fontFamily: '"Space Grotesk", sans-serif', fontWeight: 700, letterSpacing: "0.16em", textTransform: "uppercase", fontSize: 22, color: gold }}>
            Wiggle
          </p>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginTop: 22 }}>
            {choices.map((choice) => {
              const on = active?.key === choice.key;
              return (
                <div
                  key={choice.key}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "18px 18px",
                    borderRadius: 16,
                    background: on ? ink : paper,
                    color: on ? paper : ink,
                    border: "2px solid #D9D2C3",
                    fontFamily: '"Space Grotesk", sans-serif',
                    fontWeight: 700,
                    fontSize: 28,
                  }}
                >
                  <span>
                    {choice.ring ? (
                      <span style={{ display: "inline-block", width: 16, height: 16, marginRight: 8, border: "3px solid #E23B2F", borderRadius: "50%" }} />
                    ) : null}
                    {choice.label}
                  </span>
                  <span
                    style={{
                      fontSize: 20,
                      color: on ? "#FABD1A" : gold,
                      border: `2px solid ${on ? "#3A3544" : "#D9D2C3"}`,
                      borderRadius: 8,
                      padding: "2px 8px",
                      background: on ? "transparent" : "#fffdf8",
                    }}
                  >
                    {choice.key}
                  </span>
                </div>
              );
            })}
          </div>
          <p style={{ margin: "18px 0 0", minHeight: 40, fontSize: 26, color: "#4A4656" }}>{active ? active.line : "Pick one. Nothing is sent until you do."}</p>
        </div>
      </div>
      <div style={{ position: "absolute", left: 120, right: 120, bottom: 48, textAlign: "center" }}>
        <p style={{ margin: 0, fontFamily: '"Space Grotesk", sans-serif', fontWeight: 700, fontSize: 48, letterSpacing: "-0.03em" }}>{caption}</p>
      </div>
    </AbsoluteFill>
  );
};
