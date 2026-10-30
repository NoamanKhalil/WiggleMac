import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { ColdOpen, DesktopStory, Ending } from "./Scenes";
import { INK } from "./theme";
import { T } from "./timeline";

/** A 29-second pitch: the problem and a number, the wiggle, the paywall, the one-liner. */
export const WigglePitch: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: INK }}>
      {frame >= T.desktopIn[0] && frame < T.desktopOut[1] && <DesktopStory frame={frame} />}
      {frame < T.coldOpenOut[1] && <ColdOpen frame={frame} />}
      {frame >= T.endStart && <Ending frame={frame} />}
    </AbsoluteFill>
  );
};
