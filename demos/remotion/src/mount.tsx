import React from "react";
import { createRoot } from "react-dom/client";
import { Player } from "@remotion/player";
import { DURATION, FPS, WiggleAsk } from "./WiggleAsk";

const root = document.getElementById("remotion-demo");
if (root) {
  createRoot(root).render(
    <Player
      ref={(player) => {
        if (player) (root as HTMLElement & { __player?: { play: () => void; toggle: () => void } }).__player = player;
      }}
      component={WiggleAsk}
      durationInFrames={DURATION}
      compositionWidth={1920}
      compositionHeight={1080}
      fps={FPS}
      controls
      acknowledgeRemotionLicense
      style={{ width: "100%" }}
    />,
  );
}
