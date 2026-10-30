import React from "react";
import { Easing } from "remotion";
import { CAPTURED, CARD, CHOOSER_TILES, T, borderAngle, bump, clamp01, cursorAt, isBusy, ramp } from "../timeline";
import { LABEL, MONO, SECONDARY, SF, TERTIARY, conic } from "../theme";
import { Desktop } from "./Desktop";
import { GradientIcon, Icon, Spinner } from "./Icons";

export const QUESTION = "Why does everything say #REF!?";
const ANSWER = "Your Total formulas add cells one by one, and one of those columns was deleted. Replace them with ";
const FIX = "=SUM(B2:D2)";
const FIX_TAIL = " and fill down.";

// CardBackground in PromptPanel.swift: regular material, 12 pt corners, soft shadow.
const CARD_BG: React.CSSProperties = {
  background: "rgba(246, 246, 246, 0.86)",
  backdropFilter: "blur(28px) saturate(1.8)",
  boxShadow: "0 4px 20px rgba(0,0,0,0.22)",
  borderRadius: 12,
};

/** The multicolor border: 1 pt at 70% when idle, 1.5 pt and spinning while busy. */
const Border: React.FC<{ busy: boolean; angle: number }> = ({ busy, angle }) => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      borderRadius: 12,
      padding: busy ? 1.5 : 1,
      background: conic(angle),
      mask: "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)",
      maskComposite: "exclude",
      opacity: busy ? 1 : 0.7,
      pointerEvents: "none",
    }}
  />
);

/** A miniature of the captured screen. `fill` crops like `.scaledToFill()`, otherwise it fits. */
export const Thumb: React.FC<{ width: number; height: number; radius: number; fill?: boolean }> = ({ width, height, radius, fill = false }) => {
  const s = fill ? Math.max(width / 1280, height / 720) : Math.min(width / 1280, height / 720);
  const w = fill ? width : 1280 * s;
  const h = fill ? height : 720 * s;
  return (
    <div style={{ position: "relative", width: w, height: h, flex: "none", borderRadius: radius, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: (w - 1280 * s) / 2, top: (h - 720 * s) / 2, width: 1280, height: 720, transform: `scale(${s})`, transformOrigin: "0 0" }}>
        <Desktop state={CAPTURED} />
      </div>
      <div style={{ position: "absolute", inset: 0, borderRadius: radius, boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.25)" }} />
    </div>
  );
};

const IconSlot: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ width: 18, height: 18, flex: "none", display: "flex", alignItems: "center", justifyContent: "center" }}>{children}</div>
);

const Chooser: React.FC<{ frame: number }> = ({ frame: f }) => {
  const p = cursorAt(f);
  return (
    <div style={{ position: "relative", display: "flex", gap: 2, padding: 4, ...CARD_BG }}>
      <Border busy={false} angle={0} />
      {CHOOSER_TILES.map((tile) => {
        const left = CARD.x + tile.x;
        const top = CARD.y + 4;
        const hovered = p.x >= left && p.x <= left + tile.width && p.y >= top && p.y <= top + 26;
        const pressed = tile.id === "screenshot" ? bump(f, T.clickScreenshot, 6) : 0;
        return (
          <div
            key={tile.id}
            style={{
              width: tile.width,
              height: 26,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 5,
              borderRadius: 7,
              background: `rgba(0, 0, 0, ${hovered ? 0.08 + 0.08 * pressed : 0})`,
              fontSize: 12,
              fontWeight: 500,
            }}
          >
            <GradientIcon name={tile.icon} size={13} angle={hovered ? 90 : 0} />
            {tile.title}
          </div>
        );
      })}
    </div>
  );
};

const ChatCard: React.FC<{ frame: number }> = ({ frame: f }) => {
  const busy = isBusy(f);
  const capturing = f >= T.capture[0] && f < T.capture[1];
  const hasAttachment = f >= T.capture[1] && f < T.submit;
  const submitted = f >= T.submit;
  const generating = f >= T.submit && f < T.paywall;

  const typed = f >= T.submit ? 0 : Math.round(QUESTION.length * clamp01((f - T.type[0]) / (T.type[1] - T.type[0])));
  const input = QUESTION.slice(0, typed);
  const typing = f >= T.type[0] && f < T.type[1];
  const caretOn = typing || Math.floor(f / 16) % 2 === 0;
  const placeholder = capturing ? "Capturing…" : hasAttachment ? "Ask about this screen…" : submitted ? "Ask a follow-up…" : "Ask anything…";

  // Replies stream in word by word.
  const streamT = clamp01((f - T.stream[0]) / (T.stream[1] - T.stream[0]));
  let streamed = ANSWER.slice(0, Math.round(ANSWER.length * streamT));
  if (streamT < 1) streamed = streamed.slice(0, Math.max(0, streamed.lastIndexOf(" ")));
  const thinking = submitted && f < T.stream[0];
  const paywall = ramp(f, T.paywall, T.paywall + 8, Easing.out(Easing.cubic));
  const paid = f >= T.clickUnlock + 3;
  const reveal = ramp(f, T.reveal[0], T.reveal[1]);
  const press = 1 - 0.06 * bump(f, T.clickUnlock, 6);

  return (
    <div style={{ position: "relative", width: 344, ...CARD_BG }}>
      <Border busy={busy} angle={borderAngle(f)} />
      {submitted && (
        <>
          <div style={{ padding: 10, display: "flex", flexDirection: "column", gap: 4 }}>
            <div style={{ display: "flex", alignItems: "flex-start", gap: 6 }}>
              <Thumb width={48} height={30} radius={3} />
              <div style={{ fontSize: 11, fontWeight: 600, color: SECONDARY, lineHeight: "14px" }}>{QUESTION}</div>
            </div>
            {thinking ? (
              <div style={{ height: 17, display: "flex", alignItems: "center" }}>
                <Spinner size={11} frame={f} />
              </div>
            ) : (
              <div style={{ fontSize: 12.5, lineHeight: "17px", color: LABEL }}>
                {streamed}
                {paywall > 0 && (
                  <span style={{ filter: `blur(${4.5 * (1 - reveal)}px)`, opacity: paywall }}>
                    <span style={{ fontFamily: MONO, fontSize: 11.5, fontWeight: 600 }}>{FIX}</span>
                    {FIX_TAIL}
                  </span>
                )}
              </div>
            )}
            {paywall > 0 && (
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 6, height: 26, opacity: paywall, transform: `translateY(${(1 - paywall) * 6}px)` }}>
                {paid ? (
                  <div style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11.5, fontWeight: 600, color: "#1F8A4C" }}>
                    <Icon name="check" size={12} color="#1F8A4C" />
                    Paid $3.96 · Receipt sent to your manager
                  </div>
                ) : (
                  <>
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 5,
                        height: 26,
                        padding: "0 10px",
                        borderRadius: 7,
                        background: "#fff",
                        boxShadow: "0 1px 2px rgba(0,0,0,0.12), inset 0 0 0 0.5px rgba(0,0,0,0.14)",
                        fontSize: 12,
                        fontWeight: 600,
                        transform: `scale(${press})`,
                      }}
                    >
                      <Icon name="lock" size={11} color={LABEL} />
                      Unlock the fix · $3.96
                    </div>
                    <span style={{ fontSize: 10.5, color: SECONDARY }}>4x deadline surge</span>
                  </>
                )}
              </div>
            )}
          </div>
          <div style={{ height: 1, background: "rgba(0,0,0,0.06)" }} />
        </>
      )}
      {hasAttachment && (
        <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "8px 10px 0", opacity: ramp(f, T.capture[1], T.capture[1] + 6) }}>
          <Thumb width={36} height={22} radius={4} fill />
          <span style={{ fontSize: 11, fontWeight: 500, color: SECONDARY }}>Screenshot</span>
          <div style={{ flex: 1 }} />
          <Icon name="xmarkCircle" size={13} color={SECONDARY} />
        </div>
      )}
      <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "8px 10px 4px" }}>
        <GradientIcon name="sparkle" size={12} angle={0} />
        <div style={{ flex: 1, height: 18, display: "flex", alignItems: "center", fontSize: 13, whiteSpace: "nowrap", overflow: "hidden" }}>
          {input && <span style={{ color: LABEL }}>{input}</span>}
          <span style={{ display: "inline-block", width: 1.5, height: 15, marginLeft: input ? 1 : 0, marginRight: input ? 0 : 1, background: "#1d1d1f", opacity: caretOn ? 1 : 0 }} />
          {!input && <span style={{ color: TERTIARY }}>{placeholder}</span>}
        </div>
        <IconSlot>{capturing ? <Spinner size={11} frame={f} /> : <Icon name="viewfinder" size={14} color={SECONDARY} />}</IconSlot>
        <IconSlot>
          <Icon name="mic" size={14} color={SECONDARY} />
        </IconSlot>
        {generating && (
          <IconSlot>
            <Icon name="stopCircle" size={14} color={SECONDARY} />
          </IconSlot>
        )}
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", padding: "0 10px 6px", fontSize: 9.5, color: TERTIARY }}>
        <span>Apple Intelligence</span>
        <span>↩ send · esc</span>
      </div>
    </div>
  );
};

/** Wiggle's floating panel: the chooser first, then the chat card. */
export const Panel: React.FC<{ frame: number }> = ({ frame: f }) => {
  if (f < T.open || f > T.close + 6) return null;
  const appear = ramp(f, T.open, T.open + 6, Easing.out(Easing.cubic));
  const dismiss = 1 - ramp(f, T.close, T.close + 5);
  const toChat = ramp(f, T.chatStage, T.chatStage + 6, Easing.out(Easing.cubic));
  return (
    <div
      style={{
        position: "absolute",
        left: CARD.x,
        top: CARD.y,
        opacity: appear * dismiss,
        transform: `scale(${0.96 + 0.04 * appear})`,
        transformOrigin: "0 0",
        fontFamily: SF,
        color: LABEL,
      }}
    >
      {toChat < 1 && (
        <div style={{ position: "absolute", left: 0, top: 0, opacity: 1 - toChat, transform: `scale(${1 - 0.04 * toChat})`, transformOrigin: "0 0" }}>
          <Chooser frame={f} />
        </div>
      )}
      {toChat > 0 && (
        <div style={{ position: "absolute", left: 0, top: 0, opacity: toChat, transform: `scale(${0.96 + 0.04 * toChat})`, transformOrigin: "0 0" }}>
          <ChatCard frame={f} />
        </div>
      )}
    </div>
  );
};
