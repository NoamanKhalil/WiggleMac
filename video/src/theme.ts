import { loadFont } from "@remotion/google-fonts/SpaceGrotesk";

const { fontFamily } = loadFont("normal", { weights: ["500", "600", "700"], subsets: ["latin"] });

/** Pitch typography (matches the deck). */
export const DISPLAY = `"${fontFamily}", system-ui, sans-serif`;
/** macOS UI typography: renders as SF Pro on a Mac. */
export const SF = 'system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif';
export const MONO = 'ui-monospace, "SF Mono", Menlo, monospace';
export const MARKER = '"Marker Felt", "Chalkboard SE", "Comic Sans MS", cursive';

export const INK = "#14121A";
export const INK_2 = "#1F1C27";
export const INK_LINE = "#2E2A38";
export const PAPER = "#F3EFE6";
export const MUTED = "#B9B4C4";
export const FAINT = "#8E8A99";

export const BLUE = "#4285F5";
export const VIOLET = "#946BDB";
export const PINK = "#E36194";
export const RED = "#ED4D3D";
export const YELLOW = "#FABD1A";
export const GREEN = "#38B366";

/** Same stops as Palette.spectrum in the app. */
export const SPECTRUM = [BLUE, VIOLET, PINK, RED, YELLOW, GREEN, BLUE];

/** SwiftUI's AngularGradient starts at 3 o'clock; CSS conic gradients start at 12. */
export const conic = (angle: number) => `conic-gradient(from ${angle + 90}deg, ${SPECTRUM.join(", ")})`;
export const linear = (deg = 90) => `linear-gradient(${deg}deg, ${BLUE}, ${VIOLET}, ${PINK}, ${RED}, ${YELLOW}, ${GREEN})`;

/** macOS label colors, light appearance. */
export const LABEL = "rgba(0, 0, 0, 0.85)";
export const SECONDARY = "rgba(60, 60, 67, 0.6)";
export const TERTIARY = "rgba(60, 60, 67, 0.3)";
export const ERROR_RED = "#D70015";
