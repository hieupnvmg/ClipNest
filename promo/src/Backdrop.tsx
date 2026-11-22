import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";

/** Slowly drifting colour glows behind every scene, like light through glass. */
export const Backdrop = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: "#07080d", overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          width: 1300,
          height: 1300,
          left: -360,
          top: -520,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(10,132,255,0.42) 0%, rgba(10,132,255,0) 65%)",
          translate: interpolate(frame, [0, durationInFrames], ["0px 0px", "260px 180px"]),
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1200,
          height: 1200,
          right: -420,
          bottom: -560,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(175,82,222,0.36) 0%, rgba(175,82,222,0) 65%)",
          translate: interpolate(frame, [0, durationInFrames], ["0px 0px", "-240px -140px"]),
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 900,
          height: 900,
          left: 700,
          top: 420,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(48,209,88,0.16) 0%, rgba(48,209,88,0) 65%)",
          translate: interpolate(frame, [0, durationInFrames], ["0px 0px", "-320px -260px"]),
        }}
      />
      <AbsoluteFill
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
          maskImage: "radial-gradient(ellipse at center, black 30%, transparent 75%)",
        }}
      />
    </AbsoluteFill>
  );
};
