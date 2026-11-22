import type React from "react";
import { Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { fontFamily } from "./fonts";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const outExpo = Easing.bezier(0.16, 1, 0.3, 1);

export const Eyebrow = ({ text, accent, delay = 0 }: { readonly text: string; readonly accent: string; readonly delay?: number }) => {
  const frame = useCurrentFrame() - delay;
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 14,
        fontFamily,
        fontSize: 28,
        fontWeight: 700,
        letterSpacing: 4,
        textTransform: "uppercase",
        color: accent,
        opacity: interpolate(frame, [0, 12], [0, 1], clamp),
        translate: interpolate(frame, [0, 18], ["0px 20px", "0px 0px"], { ...clamp, easing: outExpo }),
      }}
    >
      <span
        style={{
          width: 14,
          height: 14,
          borderRadius: 7,
          background: accent,
          boxShadow: `0 0 18px ${accent}`,
        }}
      />
      {text}
    </div>
  );
};

/** Headline revealed word by word; the last line carries a gradient in the scene's accent colour. */
export const Headline = ({
  text,
  accent,
  align,
  size = 92,
  delay = 4,
}: {
  readonly text: string;
  readonly accent: string;
  readonly align: "center" | "left";
  readonly size?: number;
  readonly delay?: number;
}) => {
  const frame = useCurrentFrame();
  const lines = text.split("\n");
  let index = 0;
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: align === "center" ? "center" : "flex-start" }}>
      {lines.map((line, lineIndex) => {
        const last = lines.length > 1 && lineIndex === lines.length - 1;
        return (
          <div key={line} style={{ display: "flex", flexWrap: "wrap", justifyContent: align === "center" ? "center" : "flex-start", columnGap: size * 0.26 }}>
            {line.split(" ").map((word) => {
              const start = delay + index++ * 3;
              return (
                <span
                  key={word + start}
                  style={{
                    fontFamily,
                    fontSize: size,
                    fontWeight: 800,
                    lineHeight: 1.06,
                    letterSpacing: -size * 0.03,
                    color: "white",
                    background: last ? `linear-gradient(100deg, ${accent} 0%, #ffffff 120%)` : undefined,
                    WebkitBackgroundClip: last ? "text" : undefined,
                    WebkitTextFillColor: last ? "transparent" : undefined,
                    paddingBottom: 6,
                    opacity: interpolate(frame, [start, start + 10], [0, 1], clamp),
                    translate: interpolate(frame, [start, start + 20], ["0px 40px", "0px 0px"], { ...clamp, easing: outExpo }),
                    filter: `blur(${interpolate(frame, [start, start + 12], [10, 0], clamp)}px)`,
                  }}
                >
                  {word}
                </span>
              );
            })}
          </div>
        );
      })}
    </div>
  );
};

export const Subtitle = ({
  text,
  align,
  delay = 14,
  size = 38,
}: {
  readonly text: string;
  readonly align: "center" | "left";
  readonly delay?: number;
  readonly size?: number;
}) => {
  const frame = useCurrentFrame() - delay;
  return (
    <div
      style={{
        fontFamily,
        fontSize: size,
        fontWeight: 400,
        lineHeight: 1.38,
        color: "rgba(235,235,245,0.7)",
        textAlign: align,
        whiteSpace: "pre-line",
        opacity: interpolate(frame, [0, 16], [0, 1], clamp),
        translate: interpolate(frame, [0, 22], ["0px 24px", "0px 0px"], { ...clamp, easing: outExpo }),
      }}
    >
      {text}
    </div>
  );
};

/** A box that lights up part of a screenshot. Positions are fractions of the screenshot. */
export type Spot = { readonly x: number; readonly y: number; readonly w: number; readonly h: number; readonly at: number };

const Spotlight = ({ spot, accent, radius }: { readonly spot: Spot; readonly accent: string; readonly radius: number }) => {
  const frame = useCurrentFrame() - spot.at;
  return (
    <div
      style={{
        position: "absolute",
        left: `${spot.x * 100}%`,
        top: `${spot.y * 100}%`,
        width: `${spot.w * 100}%`,
        height: `${spot.h * 100}%`,
        borderRadius: radius,
        border: `4px solid ${accent}`,
        boxShadow: `0 0 0 6px ${accent}33, 0 0 50px ${accent}aa`,
        opacity: interpolate(frame, [0, 8], [0, 1], clamp),
        scale: interpolate(frame, [0, 14], [1.15, 1], { ...clamp, easing: Easing.spring({ damping: 14 }) }),
      }}
    />
  );
};

/**
 * An app screenshot that swings up out of a 3D tilt, gets one sweep of light across the glass,
 * then drifts slowly so the frame never feels static.
 */
export const Shot = ({
  image,
  accent,
  width,
  radius,
  delay = 8,
  tilt = 22,
  spots = [],
  style,
}: {
  readonly image: string;
  readonly accent: string;
  readonly width: number;
  readonly radius: number;
  readonly delay?: number;
  readonly tilt?: number;
  readonly spots?: readonly Spot[];
  readonly style?: React.CSSProperties;
}) => {
  const frame = useCurrentFrame() - delay;
  const { fps, durationInFrames } = useVideoConfig();
  const angle = interpolate(frame, [0, 1.2 * fps], [tilt, 0], { ...clamp, easing: Easing.spring({ damping: 200 }) });
  return (
    <div style={{ perspective: 2200, ...style }}>
      <div
        style={{
          position: "relative",
          width,
          borderRadius: radius,
          overflow: "hidden",
          boxShadow: `0 60px 140px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.14), 0 0 160px ${accent}45`,
          transform: `rotateX(${angle}deg)`,
          transformOrigin: "50% 100%",
          opacity: interpolate(frame, [0, 14], [0, 1], clamp),
          translate: interpolate(frame, [0, fps], ["0px 160px", "0px 0px"], { ...clamp, easing: Easing.spring({ damping: 200 }) }),
          scale: interpolate(frame, [0, durationInFrames], [0.95, 1.03], { ...clamp, easing: outExpo }),
        }}
      >
        <Img src={staticFile(image)} style={{ width: "100%", display: "block" }} />
        <div
          style={{
            position: "absolute",
            top: 0,
            bottom: 0,
            width: "35%",
            background: "linear-gradient(100deg, transparent 0%, rgba(255,255,255,0.16) 50%, transparent 100%)",
            left: `${interpolate(frame, [18, 48], [-40, 120], clamp)}%`,
          }}
        />
        {spots.map((spot) => (
          <Spotlight key={`${spot.x}-${spot.at}`} spot={spot} accent={accent} radius={radius * 0.7} />
        ))}
      </div>
    </div>
  );
};

/** A glass search pill that types its query one letter at a time, with a blinking caret. */
export const TypingPill = ({ text, at, accent, size = 40 }: { readonly text: string; readonly at: number; readonly accent: string; readonly size?: number }) => {
  const frame = useCurrentFrame() - at;
  const shown = Math.max(0, Math.min(text.length, Math.floor(frame / 3)));
  const caret = Math.floor(frame / 8) % 2 === 0 || shown < text.length;
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 18,
        padding: `${size * 0.42}px ${size * 0.8}px`,
        borderRadius: 999,
        background: "linear-gradient(180deg, rgba(255,255,255,0.16), rgba(255,255,255,0.05))",
        border: "1px solid rgba(255,255,255,0.22)",
        boxShadow: `0 20px 60px rgba(0,0,0,0.45), 0 0 40px ${accent}30, inset 0 1px 0 rgba(255,255,255,0.25)`,
        fontFamily,
        fontSize: size,
        fontWeight: 500,
        color: "white",
        opacity: interpolate(frame, [-10, 0], [0, 1], clamp),
        scale: interpolate(frame, [-10, 4], [0.9, 1], { ...clamp, easing: Easing.spring({ damping: 14 }) }),
      }}
    >
      <svg width={size * 0.9} height={size * 0.9} viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.8)" strokeWidth={2.4} strokeLinecap="round">
        <circle cx="10.5" cy="10.5" r="6.5" />
        <path d="M15.5 15.5 L21 21" />
      </svg>
      <span style={{ minWidth: size * 4 }}>
        {text.slice(0, shown)}
        <span style={{ display: "inline-block", width: 3, height: size * 0.95, marginLeft: 3, translate: "0px 6px", background: caret ? accent : "transparent" }} />
      </span>
    </div>
  );
};

export const Keycaps = ({ keys, delay = 0 }: { readonly keys: string; readonly delay?: number }) => {
  const frame = useCurrentFrame() - delay;
  return (
    <div style={{ display: "flex", gap: 18 }}>
      {keys.split(" ").map((key, index) => (
        <div
          key={key}
          style={{
            fontFamily,
            fontSize: 54,
            fontWeight: 600,
            color: "white",
            minWidth: 108,
            height: 108,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: 26,
            background: interpolate(frame, [30, 33, 40], [0, 1, 0], clamp) > 0.5
              ? "linear-gradient(180deg, rgba(10,132,255,0.75), rgba(10,132,255,0.35))"
              : "linear-gradient(180deg, rgba(255,255,255,0.20), rgba(255,255,255,0.06))",
            border: "1px solid rgba(255,255,255,0.24)",
            boxShadow: "0 12px 34px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.28)",
            opacity: interpolate(frame, [index * 5, index * 5 + 10], [0, 1], clamp),
            translate: interpolate(
              frame,
              [index * 5, index * 5 + 16, 30, 34, 42],
              ["0px -50px", "0px 0px", "0px 0px", "0px 9px", "0px 0px"],
              clamp,
            ),
          }}
        >
          {key}
        </div>
      ))}
    </div>
  );
};

/** A small rounded tag, used for the lists under a feature. */
export const Chip = ({ label, accent, at }: { readonly label: string; readonly accent: string; readonly at: number }) => {
  const frame = useCurrentFrame() - at;
  return (
    <div
      style={{
        fontFamily,
        fontSize: 28,
        fontWeight: 600,
        color: "white",
        padding: "12px 24px",
        borderRadius: 999,
        background: `${accent}26`,
        border: `1px solid ${accent}80`,
        opacity: interpolate(frame, [0, 8], [0, 1], clamp),
        scale: interpolate(frame, [0, 14], [0.6, 1], { ...clamp, easing: Easing.spring({ damping: 12 }) }),
      }}
    >
      {label}
    </div>
  );
};
