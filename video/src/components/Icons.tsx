import React from "react";
import { conic } from "../theme";

// Stand-ins for the SF Symbols the app uses, drawn on a 24×24 grid. Only alpha matters: they're used as masks.
const SVG: Record<string, string> = {
  bubble:
    '<path d="M12 3.5C6.75 3.5 2.5 7 2.5 11.3c0 2.45 1.38 4.63 3.55 6.06-.2 1.44-.86 2.63-1.93 3.5 2.2.12 4.13-.62 5.46-1.83.78.14 1.58.21 2.42.21 5.25 0 9.5-3.5 9.5-7.94S17.25 3.5 12 3.5z"/>',
  viewfinder:
    '<path d="M3.5 8V6a2.5 2.5 0 0 1 2.5-2.5h2M16 3.5h2A2.5 2.5 0 0 1 20.5 6v2M20.5 16v2a2.5 2.5 0 0 1-2.5 2.5h-2M8 20.5H6A2.5 2.5 0 0 1 3.5 18v-2" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round"/><path fill-rule="evenodd" d="M8.4 9.3h1.7l.9-1.4h2l.9 1.4h1.7a1.1 1.1 0 0 1 1.1 1.1v4.6a1.1 1.1 0 0 1-1.1 1.1H8.4a1.1 1.1 0 0 1-1.1-1.1v-4.6a1.1 1.1 0 0 1 1.1-1.1zM12 10.9a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 0 0 0-3.6z"/>',
  micFill:
    '<rect x="8.5" y="2.5" width="7" height="12" rx="3.5"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3" fill="none" stroke="#000" stroke-width="2"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round"/>',
  sparkle: '<path d="M12 2c.8 5.5 4.5 9.2 10 10-5.5.8-9.2 4.5-10 10-.8-5.5-4.5-9.2-10-10 5.5-.8 9.2-4.5 10-10z"/>',
  xmarkCircle:
    '<path fill-rule="evenodd" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM8.7 7.3l3.3 3.3 3.3-3.3 1.4 1.4-3.3 3.3 3.3 3.3-1.4 1.4-3.3-3.3-3.3 3.3-1.4-1.4 3.3-3.3-3.3-3.3z"/>',
  stopCircle: '<path fill-rule="evenodd" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM9 8h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/>',
  lock: '<path d="M7.5 10.5V7.5a4.5 4.5 0 0 1 9 0v3" fill="none" stroke="#000" stroke-width="2.4"/><rect x="4.5" y="10" width="15" height="11.5" rx="2.5"/>',
  check: '<path d="M5 12.5l4.2 4.2L19 7" fill="none" stroke="#000" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>',
  wiggleStatus:
    '<path d="M10.5 3.5v14l3.2-3 2.3 5.2 2.3-1-2.3-5.1h4.5z"/><path d="M2.5 9h5M2 12.5h5.5M3.5 16h4" fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round"/>',
  wifi: '<path d="M2.5 8.8a13.5 13.5 0 0 1 19 0M5.6 12a9 9 0 0 1 12.8 0M8.7 15.1a4.6 4.6 0 0 1 6.6 0" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="18.6" r="1.7"/>',
};

export type IconName = keyof typeof SVG;

const maskUrl = (name: IconName) =>
  `url("data:image/svg+xml;utf8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">${SVG[name]}</svg>`)}")`;

const masked = (name: IconName, size: number, background: string): React.CSSProperties => ({
  width: size,
  height: size,
  flex: "none",
  background,
  WebkitMaskImage: maskUrl(name),
  maskImage: maskUrl(name),
  WebkitMaskSize: "contain",
  maskSize: "contain",
  WebkitMaskRepeat: "no-repeat",
  maskRepeat: "no-repeat",
  WebkitMaskPosition: "center",
  maskPosition: "center",
});

export const Icon: React.FC<{ name: IconName; size: number; color: string }> = ({ name, size, color }) => (
  <div style={masked(name, size, color)} />
);

/** An icon filled with the app's multicolor sweep, like `.foregroundStyle(Palette.sweep(angle:))`. */
export const GradientIcon: React.FC<{ name: IconName; size: number; angle: number }> = ({ name, size, angle }) => (
  <div style={masked(name, size, conic(angle))} />
);

/** ProgressView with `.controlSize(.mini)`. */
export const Spinner: React.FC<{ size: number; frame: number; color?: string }> = ({ size, frame, color = "#3c3c43" }) => {
  const head = Math.floor(frame / 2) % 8;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ flex: "none" }}>
      {Array.from({ length: 8 }, (_, i) => {
        const age = (head - i + 8) % 8;
        return (
          <line
            key={i}
            x1={12}
            y1={3}
            x2={12}
            y2={8}
            stroke={color}
            strokeWidth={2.6}
            strokeLinecap="round"
            opacity={1 - age * 0.11}
            transform={`rotate(${i * 45} 12 12)`}
          />
        );
      })}
    </svg>
  );
};
