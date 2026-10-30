import React from "react";
import { DesktopState, GRID, WIN, WORLD } from "../timeline";
import { ERROR_RED, MARKER, MONO, SF } from "../theme";
import { Icon } from "./Icons";

// Q3 Budget. Column E ("Total") breaks with #REF! because a column it referenced was deleted.
const ITEMS: [string, number, number, number][] = [
  ["Software", 1240, 1310, 1290],
  ["Travel", 860, 2140, 990],
  ["Office", 420, 380, 455],
  ["Coffee", 310, 520, 1180],
  ["Snacks", 210, 340, 960],
  ["Emergency snacks", 0, 85, 1420],
];
const TOTALS = [3040, 4775, 6295];
const fmt = (n: number) => n.toLocaleString("en-US");

const GRID_LINE = "#e4e4e4";
const HEADER_BG = "#f3f3f3";
const SELECT_BLUE = "#0A84FF";

const columnX = (index: number) => GRID.rowNumber + GRID.columns.slice(0, index).reduce((a, b) => a + b, 0);
const rowY = (row: number) => GRID.header + (row - 1) * GRID.row;

const Cell: React.FC<{
  col: number;
  row: number;
  align?: "left" | "right" | "center";
  style?: React.CSSProperties;
  children?: React.ReactNode;
}> = ({ col, row, align = "right", style, children }) => (
  <div
    style={{
      position: "absolute",
      left: columnX(col),
      top: rowY(row),
      width: GRID.columns[col],
      height: GRID.row,
      display: "flex",
      alignItems: "center",
      justifyContent: align === "left" ? "flex-start" : align === "center" ? "center" : "flex-end",
      padding: "0 8px",
      borderRight: `1px solid ${GRID_LINE}`,
      borderBottom: `1px solid ${GRID_LINE}`,
      fontSize: 12.5,
      fontVariantNumeric: "tabular-nums",
      whiteSpace: "nowrap",
      ...style,
    }}
  >
    {children}
  </div>
);

const Sheet: React.FC<{ state: DesktopState }> = ({ state }) => {
  const width = columnX(GRID.columns.length);
  const height = rowY(9);
  const totalCell = (i: number, value: number) => {
    const row = state.rows[i];
    const bold = i === 6;
    if (row.broken) {
      return (
        <Cell col={4} row={i + 2} style={{ background: `rgba(215, 0, 21, ${0.07 + 0.25 * row.flash})`, color: ERROR_RED, fontWeight: 700 }}>
          #REF!
        </Cell>
      );
    }
    return (
      <Cell col={4} row={i + 2} style={{ background: `rgba(52, 199, 89, ${0.3 * row.fixFlash})`, fontWeight: bold ? 700 : 400 }}>
        {fmt(value)}
      </Cell>
    );
  };

  return (
    <div style={{ position: "absolute", left: GRID.left, top: GRID.top, width, height }}>
      {/* Column letters */}
      <div style={{ position: "absolute", left: 0, top: 0, width: GRID.rowNumber, height: GRID.header, background: HEADER_BG, borderRight: `1px solid ${GRID_LINE}`, borderBottom: `1px solid ${GRID_LINE}` }} />
      {["A", "B", "C", "D", "E"].map((letter, i) => (
        <div
          key={letter}
          style={{
            position: "absolute",
            left: columnX(i),
            top: 0,
            width: GRID.columns[i],
            height: GRID.header,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 11,
            color: state.selected && i === 4 ? "#0A5AD1" : "#6e6e73",
            fontWeight: state.selected && i === 4 ? 600 : 400,
            background: state.selected && i === 4 ? "#DCE8FB" : HEADER_BG,
            borderRight: `1px solid ${GRID_LINE}`,
            borderBottom: `1px solid ${GRID_LINE}`,
          }}
        >
          {letter}
        </div>
      ))}
      {/* Row numbers */}
      {Array.from({ length: 8 }, (_, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: 0,
            top: rowY(i + 1),
            width: GRID.rowNumber,
            height: GRID.row,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 11,
            color: state.selected && i === 6 ? "#0A5AD1" : "#6e6e73",
            fontWeight: state.selected && i === 6 ? 600 : 400,
            background: state.selected && i === 6 ? "#DCE8FB" : HEADER_BG,
            borderRight: `1px solid ${GRID_LINE}`,
            borderBottom: `1px solid ${GRID_LINE}`,
          }}
        >
          {i + 1}
        </div>
      ))}
      {/* Header row */}
      {["Item", "Jul", "Aug", "Sep", "Total"].map((label, i) => (
        <Cell key={label} col={i} row={1} align={i === 0 ? "left" : "right"} style={{ fontWeight: 600, background: "#fafafa" }}>
          {label}
        </Cell>
      ))}
      {ITEMS.map(([name, jul, aug, sep], i) => (
        <React.Fragment key={name}>
          <Cell col={0} row={i + 2} align="left">
            {name}
          </Cell>
          <Cell col={1} row={i + 2}>{fmt(jul)}</Cell>
          <Cell col={2} row={i + 2}>{fmt(aug)}</Cell>
          <Cell col={3} row={i + 2}>{fmt(sep)}</Cell>
          {totalCell(i, jul + aug + sep)}
        </React.Fragment>
      ))}
      <Cell col={0} row={8} align="left" style={{ fontWeight: 700 }}>
        Total
      </Cell>
      {TOTALS.map((t, i) => (
        <Cell key={i} col={i + 1} row={8} style={{ fontWeight: 700 }}>
          {fmt(t)}
        </Cell>
      ))}
      {totalCell(6, TOTALS.reduce((a, b) => a + b, 0))}
      {/* Selection on E7 */}
      {state.selected && (
        <div
          style={{
            position: "absolute",
            left: columnX(4) - 1,
            top: rowY(7) - 1,
            width: GRID.columns[4] + 1,
            height: GRID.row + 1,
            border: `2px solid ${SELECT_BLUE}`,
          }}
        >
          <div style={{ position: "absolute", right: -4, bottom: -4, width: 6, height: 6, background: SELECT_BLUE, border: "1px solid #fff" }} />
        </div>
      )}
    </div>
  );
};

const FormulaBar: React.FC<{ state: DesktopState }> = ({ state }) => (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: 52,
      width: WIN.width,
      height: 30,
      display: "flex",
      alignItems: "center",
      borderBottom: "1px solid #e2e2e2",
      background: "#fff",
    }}
  >
    <div style={{ width: 70, height: "100%", display: "flex", alignItems: "center", paddingLeft: 14, borderRight: "1px solid #e2e2e2", fontSize: 12, fontWeight: 600, color: "#1d1d1f" }}>
      {state.formula === "empty" ? "A1" : "E7"}
    </div>
    <div style={{ padding: "0 10px", fontFamily: "Georgia, serif", fontStyle: "italic", fontSize: 13, color: "#8a8a8e" }}>fx</div>
    <div style={{ fontFamily: MONO, fontSize: 12.5, color: "#1d1d1f" }}>
      {state.formula === "broken" && (
        <>
          =B7+C7+D7+<span style={{ color: ERROR_RED, fontWeight: 700 }}>#REF!</span>
        </>
      )}
      {state.formula === "fixed" && "=SUM(B7:D7)"}
    </div>
  </div>
);

const Window: React.FC<{ state: DesktopState }> = ({ state }) => (
  <div
    style={{
      position: "absolute",
      left: WIN.x,
      top: WIN.y,
      width: WIN.width,
      height: WIN.height,
      borderRadius: 14,
      background: "#fff",
      overflow: "hidden",
      boxShadow: "0 24px 70px rgba(0,0,0,0.45), 0 0 0 0.5px rgba(0,0,0,0.3)",
    }}
  >
    {/* Toolbar */}
    <div style={{ position: "absolute", left: 0, top: 0, width: WIN.width, height: 52, background: "#f4f3f2", borderBottom: "1px solid #e2e2e2" }}>
      <div style={{ position: "absolute", left: 18, top: 20, display: "flex", gap: 8 }}>
        {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
          <div key={c} style={{ width: 12, height: 12, borderRadius: 6, background: c, boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.15)" }} />
        ))}
      </div>
      <div style={{ position: "absolute", left: 92, top: 10 }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: "#1d1d1f" }}>Q3 Budget</div>
        <div style={{ fontSize: 11, color: "#8a8a8e" }}>Edited just now</div>
      </div>
      <div style={{ position: "absolute", right: 16, top: 14, display: "flex", gap: 10 }}>
        {["Table", "Chart", "Text"].map((label) => (
          <div key={label} style={{ height: 24, padding: "0 10px", borderRadius: 6, background: "#e8e7e6", fontSize: 11.5, color: "#3c3c43", display: "flex", alignItems: "center" }}>
            {label}
          </div>
        ))}
        <div style={{ height: 24, padding: "0 12px", borderRadius: 6, background: "#0A84FF", fontSize: 11.5, fontWeight: 600, color: "#fff", display: "flex", alignItems: "center" }}>Share</div>
      </div>
    </div>
    <FormulaBar state={state} />
    <Sheet state={state} />
    {/* Sticky note */}
    <div
      style={{
        position: "absolute",
        left: 670,
        top: 118,
        width: 164,
        padding: "16px 16px 18px",
        background: "linear-gradient(180deg, #FFF1A6, #FFE56B)",
        boxShadow: "0 8px 18px rgba(0,0,0,0.18)",
        transform: "rotate(4deg)",
        fontFamily: MARKER,
        fontSize: 19,
        lineHeight: 1.2,
        color: "#3A3000",
      }}
    >
      CFO wants this by <span style={{ color: "#C4271B" }}>5 PM!!!</span>
    </div>
  </div>
);

const MenuBar: React.FC<{ clock: string }> = ({ clock }) => (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: 0,
      width: WORLD.width,
      height: 24,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "0 14px",
      background: "rgba(246, 246, 246, 0.6)",
      backdropFilter: "blur(20px) saturate(1.8)",
      fontSize: 13,
      color: "#1d1d1f",
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
      <span style={{ fontSize: 15 }}>{""}</span>
      <span style={{ fontWeight: 700 }}>Spreadsheet</span>
      {["File", "Edit", "Insert", "Table", "Format", "Window", "Help"].map((item) => (
        <span key={item}>{item}</span>
      ))}
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
      <Icon name="wiggleStatus" size={17} color="#1d1d1f" />
      <Icon name="wifi" size={15} color="#1d1d1f" />
      <div style={{ display: "flex", alignItems: "center", gap: 1 }}>
        <div style={{ width: 22, height: 11, borderRadius: 3, border: "1px solid rgba(29,29,31,0.55)", padding: 1.5 }}>
          <div style={{ width: "62%", height: "100%", borderRadius: 1.5, background: "#1d1d1f" }} />
        </div>
        <div style={{ width: 1.5, height: 4, borderRadius: 1, background: "rgba(29,29,31,0.55)" }} />
      </div>
      <span style={{ fontVariantNumeric: "tabular-nums" }}>Mon Oct 5&nbsp;&nbsp;{clock}</span>
    </div>
  </div>
);

const Notification: React.FC<{ notify: DesktopState["notify"] }> = ({ notify }) => {
  if (notify.slide <= 0) return null;
  return (
    <div
      style={{
        position: "absolute",
        right: 12,
        top: 32,
        width: 344,
        display: "flex",
        gap: 10,
        padding: "11px 12px",
        borderRadius: 18,
        background: "rgba(248, 248, 248, 0.88)",
        backdropFilter: "blur(24px) saturate(1.8)",
        boxShadow: "0 10px 30px rgba(0,0,0,0.28), 0 0 0 0.5px rgba(0,0,0,0.12)",
        transform: `translateX(${(1 - notify.slide) * 380}px) scale(${1 + 0.05 * notify.bump})`,
        transformOrigin: "right top",
      }}
    >
      <div style={{ width: 36, height: 36, flex: "none", borderRadius: 8, background: "#fff", overflow: "hidden", boxShadow: "0 0 0 0.5px rgba(0,0,0,0.15)" }}>
        <div style={{ height: 11, background: "#FF3B30", color: "#fff", fontSize: 7.5, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center", letterSpacing: 0.5 }}>OCT</div>
        <div style={{ fontSize: 18, fontWeight: 500, color: "#1d1d1f", textAlign: "center", lineHeight: "24px" }}>5</div>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: "#1d1d1f" }}>Budget review with CFO</span>
          <span style={{ fontSize: 11, color: "#8a8a8e" }}>now</span>
        </div>
        <div style={{ fontSize: 12.5, color: "#3c3c43", marginTop: 1 }}>
          Due at 5:00 PM ·{" "}
          <span style={{ color: notify.urgent ? ERROR_RED : "#3c3c43", fontWeight: notify.urgent ? 700 : 400 }}>{notify.body}</span>
        </div>
      </div>
    </div>
  );
};

/** The Mac's screen: wallpaper, menu bar, the broken spreadsheet and the calendar reminder. */
export const Desktop: React.FC<{ state: DesktopState }> = ({ state }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: WORLD.width, height: WORLD.height, overflow: "hidden", fontFamily: SF }}>
    <div
      style={{
        position: "absolute",
        inset: 0,
        background: [
          "radial-gradient(60% 70% at 88% 108%, rgba(250, 189, 26, 0.6), transparent 70%)",
          "radial-gradient(55% 70% at 0% 100%, rgba(227, 97, 148, 0.6), transparent 70%)",
          "radial-gradient(70% 60% at 55% -10%, rgba(66, 133, 245, 0.65), transparent 70%)",
          "linear-gradient(160deg, #1B1F4A 0%, #3B2F7A 45%, #7A3D78 75%, #C0654F 100%)",
        ].join(", "),
      }}
    />
    <Window state={state} />
    <MenuBar clock={state.clock} />
    <Notification notify={state.notify} />
  </div>
);
