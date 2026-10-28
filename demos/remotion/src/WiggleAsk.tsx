import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";

export const FPS = 30;
export const DURATION = 360;

const ink = "#14121A";
const paper = "#F3EFE6";
const muted = "#B9B4C4";
const gold = "#8A5A00";

const fade = (frame: number, start: number, end: number) => {
  if (frame < start || frame > end) return 0;
  const fadeIn =
    start === 0
      ? 1
      : interpolate(frame, [start, start + 12], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
  const fadeOut =
    end >= DURATION - 1
      ? 1
      : interpolate(frame, [end - 12, end], [1, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
  return Math.min(fadeIn, fadeOut);
};

const Card: React.FC<{ kicker: string; title: string; body: string; opacity: number }> = ({
  kicker,
  title,
  body,
  opacity,
}) => (
  <AbsoluteFill style={{ opacity, justifyContent: "center", alignItems: "center", padding: 120 }}>
    <div
      style={{
        width: 1280,
        background: "#fffdf8",
        color: ink,
        borderRadius: 36,
        padding: "64px 72px",
      }}
    >
      <p
        style={{
          margin: 0,
          fontFamily: '"Space Grotesk", sans-serif',
          fontWeight: 700,
          letterSpacing: "0.14em",
          textTransform: "uppercase",
          fontSize: 28,
          color: gold,
        }}
      >
        {kicker}
      </p>
      <h2
        style={{
          margin: "18px 0 0",
          fontFamily: '"Space Grotesk", sans-serif',
          fontWeight: 700,
          fontSize: 92,
          letterSpacing: "-0.04em",
          lineHeight: 1.02,
        }}
      >
        {title}
      </h2>
      <p style={{ margin: "28px 0 0", fontSize: 40, lineHeight: 1.35, color: "#4A4656" }}>{body}</p>
    </div>
  </AbsoluteFill>
);

export const WiggleAsk: React.FC = () => {
  const frame = useCurrentFrame();
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
      <AbsoluteFill style={{ opacity: fade(frame, 0, 70), justifyContent: "center", padding: 140 }}>
        <p style={{ margin: 0, color: muted, fontSize: 32, letterSpacing: "0.14em", textTransform: "uppercase" }}>
          Wiggle for Mac
        </p>
        <h1
          style={{
            margin: "18px 0 0",
            fontFamily: '"Space Grotesk", sans-serif',
            fontWeight: 700,
            fontSize: 120,
            letterSpacing: "-0.045em",
            lineHeight: 0.98,
          }}
        >
          Three ways to ask.
        </h1>
        <p style={{ margin: "28px 0 0", fontSize: 42, color: muted, maxWidth: 1200 }}>
          You pick one each time Wiggle opens. This film does not send a message.
        </p>
      </AbsoluteFill>
      <Card
        kicker="1 · Chat"
        title="Ask in writing."
        body="About whatever is already on screen, without leaving the spot where you got stuck."
        opacity={fade(frame, 70, 150)}
      />
      <Card
        kicker="2 · Screenshot"
        title="You choose the picture."
        body="A screenshot happens when you pick Screenshot. It is not taken while you work."
        opacity={fade(frame, 150, 230)}
      />
      <Card
        kicker="3 · Voice"
        title="Ask out loud."
        body="Voice is a mode you pick, like Chat or Screenshot. It is not a microphone that stays on."
        opacity={fade(frame, 230, 310)}
      />
      <AbsoluteFill style={{ opacity: fade(frame, 310, 360), justifyContent: "center", padding: 140 }}>
        <p style={{ margin: 0, color: gold, fontFamily: '"Space Grotesk", sans-serif', fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase", fontSize: 28 }}>
          The model
        </p>
        <h2
          style={{
            margin: "18px 0 0",
            fontFamily: '"Space Grotesk", sans-serif',
            fontWeight: 700,
            fontSize: 78,
            letterSpacing: "-0.04em",
            lineHeight: 1.05,
            maxWidth: 1500,
          }}
        >
          Apple Intelligence, Ollama, or your own key.
        </h2>
        <p style={{ margin: "28px 0 0", fontSize: 36, color: muted }}>Early access. No account.</p>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
