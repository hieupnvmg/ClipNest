import {
  Easing,
  Img,
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { fontFamily } from "./fonts";

type Copy = {
  readonly eyebrow: string;
  readonly title: string;
  readonly subtitle: string;
  readonly accent: string;
  readonly image: string;
};

const Eyebrow = ({ text, accent }: { readonly text: string; readonly accent: string }) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        fontFamily,
        fontSize: 30,
        fontWeight: 600,
        letterSpacing: 4,
        textTransform: "uppercase",
        color: accent,
        opacity: interpolate(frame, [0, 12], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        translate: interpolate(frame, [0, 18], ["0px 24px", "0px 0px"], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
      }}
    >
      {text}
    </div>
  );
};

const Headline = ({ text, align }: { readonly text: string; readonly align: "center" | "left" }) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        fontFamily,
        fontSize: 88,
        fontWeight: 800,
        lineHeight: 1.04,
        letterSpacing: -2.5,
        color: "white",
        textAlign: align,
        whiteSpace: "pre-line",
        opacity: interpolate(frame, [4, 18], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        translate: interpolate(frame, [4, 26], ["0px 36px", "0px 0px"], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
      }}
    >
      {text}
    </div>
  );
};

const Subtitle = ({ text, align }: { readonly text: string; readonly align: "center" | "left" }) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        fontFamily,
        fontSize: 40,
        fontWeight: 400,
        lineHeight: 1.35,
        color: "rgba(235,235,245,0.68)",
        textAlign: align,
        whiteSpace: "pre-line",
        opacity: interpolate(frame, [10, 26], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        translate: interpolate(frame, [10, 32], ["0px 28px", "0px 0px"], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
      }}
    >
      {text}
    </div>
  );
};

/** The app screenshot: rises in on a spring, then drifts slowly so the frame never feels static. */
const Shot = ({
  image,
  accent,
  width,
  radius,
}: {
  readonly image: string;
  readonly accent: string;
  readonly width: number;
  readonly radius: number;
}) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  return (
    <div
      style={{
        width,
        borderRadius: radius,
        overflow: "hidden",
        boxShadow: `0 50px 120px rgba(0,0,0,0.65), 0 0 0 1px rgba(255,255,255,0.12), 0 0 120px ${accent}40`,
        opacity: interpolate(frame, [8, 24], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        translate: interpolate(frame, [8, 8 + fps], ["0px 140px", "0px 0px"], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.spring({ damping: 200 }),
        }),
        scale: interpolate(frame, [8, durationInFrames], [0.94, 1.02], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
          output: "perceptual-scale",
        }),
      }}
    >
      <Img src={staticFile(image)} style={{ width: "100%", display: "block" }} />
    </div>
  );
};

const Keycaps = ({ keys }: { readonly keys: string }) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ display: "flex", gap: 18, marginBottom: 6 }}>
      {keys.split(" ").map((key, index) => (
        <div
          key={key}
          style={{
            fontFamily,
            fontSize: 54,
            fontWeight: 600,
            color: "white",
            minWidth: 104,
            height: 104,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: 24,
            background: "linear-gradient(180deg, rgba(255,255,255,0.20), rgba(255,255,255,0.06))",
            border: "1px solid rgba(255,255,255,0.22)",
            boxShadow: "0 10px 30px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.25)",
            // Each key drops in, then all three press down together.
            opacity: interpolate(frame, [index * 5, index * 5 + 10], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            }),
            translate: interpolate(frame, [index * 5, index * 5 + 16, 30, 34, 40], ["0px -40px", "0px 0px", "0px 0px", "0px 8px", "0px 0px"], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            }),
          }}
        >
          {key}
        </div>
      ))}
    </div>
  );
};

/** A feature with a wide panel screenshot under a centred headline. */
const WideFeatureInner = ({
  eyebrow,
  title,
  subtitle,
  accent,
  image,
  keys,
}: Copy & { readonly keys: string }) => (
  <>
    <div
      style={{
        position: "absolute",
        top: 110,
        left: 100,
        right: 100,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 20,
      }}
    >
      {keys ? <Keycaps keys={keys} /> : <Eyebrow text={eyebrow} accent={accent} />}
      <Headline text={title} align="center" />
      <Subtitle text={subtitle} align="center" />
    </div>
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 90, display: "flex", justifyContent: "center" }}>
      <Shot image={image} accent={accent} width={1720} radius={34} />
    </div>
  </>
);

export const WideFeature = Interactive.create({
  Component: WideFeatureInner,
  layout: "absolute-fill",
  schema: {
    eyebrow: { type: "string", default: "Feature", description: "Eyebrow" },
    title: { type: "string", default: "Title", description: "Headline" },
    subtitle: { type: "string", default: "", description: "Subtitle" },
    accent: { type: "color", default: "#0A84FF", description: "Accent colour" },
    image: { type: "string", default: "panel.png", description: "Screenshot in public/" },
    keys: { type: "string", default: "", description: "Keycaps, separated by spaces" },
  },
});

/** A feature with copy on the left and a window screenshot on the right. */
const SplitFeatureInner = ({
  eyebrow,
  title,
  subtitle,
  accent,
  image,
  imageWidth,
}: Copy & { readonly imageWidth: number }) => (
  <>
    <div
      style={{
        position: "absolute",
        left: 120,
        top: 0,
        bottom: 0,
        width: 760,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 26,
      }}
    >
      <Eyebrow text={eyebrow} accent={accent} />
      <Headline text={title} align="left" />
      <Subtitle text={subtitle} align="left" />
    </div>
    <div
      style={{
        position: "absolute",
        right: 110,
        top: 0,
        bottom: 0,
        display: "flex",
        alignItems: "center",
      }}
    >
      <Shot image={image} accent={accent} width={imageWidth} radius={26} />
    </div>
  </>
);

export const SplitFeature = Interactive.create({
  Component: SplitFeatureInner,
  layout: "absolute-fill",
  schema: {
    eyebrow: { type: "string", default: "Feature", description: "Eyebrow" },
    title: { type: "string", default: "Title", description: "Headline" },
    subtitle: { type: "string", default: "", description: "Subtitle" },
    accent: { type: "color", default: "#0A84FF", description: "Accent colour" },
    image: { type: "string", default: "sync.png", description: "Screenshot in public/" },
    imageWidth: { type: "number", default: 860, min: 300, max: 1200, step: 10, hiddenFromList: false, description: "Screenshot width" },
  },
});

/** Opening and closing card: app icon, name and a line under it. */
const BrandInner = ({ tagline, footer }: { readonly tagline: string; readonly footer: string }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 28 }}>
      <Img
        name="App icon"
        src={staticFile("icon.png")}
        style={{
          width: 300,
          height: 300,
          filter: "drop-shadow(0 40px 80px rgba(10,132,255,0.45))",
          scale: interpolate(frame, [0, fps], [0.4, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.spring({ damping: 12 }),
            output: "perceptual-scale",
          }),
          rotate: interpolate(frame, [0, fps], ["-12deg", "0deg"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.spring({ damping: 14 }),
          }),
          opacity: interpolate(frame, [0, 8], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        }}
      />
      <Interactive.Div
        name="App name"
        style={{
          fontFamily,
          fontSize: 140,
          fontWeight: 800,
          letterSpacing: -5,
          color: "white",
          opacity: interpolate(frame, [10, 24], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
          translate: interpolate(frame, [10, 34], ["0px 40px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        ClipNest
      </Interactive.Div>
      <Subtitle text={tagline} align="center" />
      {footer ? (
        <div
          style={{
            marginTop: 18,
            display: "flex",
            gap: 22,
            alignItems: "center",
            opacity: interpolate(frame, [22, 38], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
          }}
        >
          <div
            style={{
              fontFamily,
              fontSize: 40,
              fontWeight: 600,
              color: "white",
              padding: "22px 46px",
              borderRadius: 999,
              background: "linear-gradient(180deg, #2E9BFF, #0A6CFF)",
              boxShadow: "0 18px 50px rgba(10,132,255,0.5), inset 0 1px 0 rgba(255,255,255,0.35)",
            }}
          >
            Download for Mac
          </div>
          <div style={{ fontFamily, fontSize: 36, fontWeight: 500, color: "rgba(235,235,245,0.7)" }}>{footer}</div>
        </div>
      ) : null}
    </div>
  );
};

export const Brand = Interactive.create({
  Component: BrandInner,
  layout: "absolute-fill",
  schema: {
    tagline: { type: "string", default: "", description: "Tagline" },
    footer: { type: "string", default: "", description: "Footer next to the download button" },
  },
});
