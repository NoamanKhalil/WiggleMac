import React from "react";
import { Composition } from "remotion";
import { WigglePitch } from "./WigglePitch";
import { DURATION, FPS } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <Composition id="WigglePitch" component={WigglePitch} durationInFrames={DURATION} fps={FPS} width={1920} height={1080} />
);
