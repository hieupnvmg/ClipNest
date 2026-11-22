import { Easing, Img, Interactive, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { fontFamily, monoFamily } from "./fonts";
import { Chip, Eyebrow, Headline, Keycaps, Shot, type Spot, Subtitle, TypingPill } from "./Parts";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const outExpo = Easing.bezier(0.16, 1, 0.3, 1);

const textSchema = {
  eyebrow: { type: "string", default: "Feature", description: "Eyebrow" },
  title: { type: "string", default: "Title", description: "Headline (new line = gradient line)" },
  subtitle: { type: "string", default: "", description: "Subtitle" },
  accent: { type: "color", default: "#0A84FF", description: "Accent colour" },
} as const;

type Copy = {
  readonly eyebrow: string;
  readonly title: string;
  readonly subtitle: string;
  readonly accent: string;
};

/* ───────────── Wide panel screenshot under a centred headline ───────────── */

const WideFeatureInner = ({
  eyebrow,
  title,
  subtitle,
  accent,
  image,
  keys,
  spots = [],
}: Copy & { readonly image: string; readonly keys: string; readonly spots?: readonly Spot[] }) => (
  <>
    <div
      style={{
        position: "absolute",
        top: 96,
        left: 100,
        right: 100,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 22,
      }}
    >
      {keys ? <Keycaps keys={keys} /> : <Eyebrow text={eyebrow} accent={accent} />}
      <Headline text={title} accent={accent} align="center" size={keys ? 88 : 92} delay={keys ? 10 : 4} />
      <Subtitle text={subtitle} align="center" />
    </div>
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 80, display: "flex", justifyContent: "center" }}>
      <Shot image={image} accent={accent} width={1720} radius={34} delay={keys ? 36 : 10} spots={spots} />
    </div>
  </>
);

export const WideFeature = Interactive.create({
  Component: WideFeatureInner,
  layout: "absolute-fill",
  schema: {
    ...textSchema,
    image: { type: "string", default: "panel.png", description: "Screenshot in public/" },
    keys: { type: "string", default: "", description: "Keycaps, separated by spaces" },
  },
});

/* ───────────── Copy on the left, a window screenshot on the right ───────────── */

const SplitFeatureInner = ({
  eyebrow,
  title,
  subtitle,
  accent,
  image,
  imageWidth,
  typed,
  chips,
  spots = [],
}: Copy & {
  readonly image: string;
  readonly imageWidth: number;
  readonly typed: string;
  readonly chips: string;
  readonly spots?: readonly Spot[];
}) => (
  <>
    <div
      style={{
        position: "absolute",
        left: 120,
        top: 0,
        bottom: 0,
        width: 1700 - imageWidth - 120,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 28,
      }}
    >
      <Eyebrow text={eyebrow} accent={accent} />
      <Headline text={title} accent={accent} align="left" />
      <Subtitle text={subtitle} align="left" />
      {typed ? (
        <div style={{ marginTop: 8 }}>
          <TypingPill text={typed} at={24} accent={accent} />
        </div>
      ) : null}
      {chips ? (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 14, marginTop: 8 }}>
          {chips.split(",").map((chip, index) => (
            <Chip key={chip} label={chip.trim()} accent={accent} at={30 + index * 4} />
          ))}
        </div>
      ) : null}
    </div>
    <div style={{ position: "absolute", right: 100, top: 0, bottom: 0, display: "flex", alignItems: "center" }}>
      <Shot image={image} accent={accent} width={imageWidth} radius={26} spots={spots} />
    </div>
  </>
);

export const SplitFeature = Interactive.create({
  Component: SplitFeatureInner,
  layout: "absolute-fill",
  schema: {
    ...textSchema,
    image: { type: "string", default: "sync.png", description: "Screenshot in public/" },
    imageWidth: { type: "number", default: 860, min: 300, max: 1200, step: 10, hiddenFromList: false, description: "Screenshot width" },
    typed: { type: "string", default: "", description: "Search text typed under the copy" },
    chips: { type: "string", default: "", description: "Comma-separated tags under the copy" },
  },
});

/* ───────────── Opening and closing card ───────────── */

const BrandInner = ({ tagline, footer }: { readonly tagline: string; readonly footer: string }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 26 }}>
      <div style={{ position: "relative" }}>
        <div
          style={{
            position: "absolute",
            inset: -120,
            borderRadius: "50%",
            background: "radial-gradient(circle, rgba(10,132,255,0.55) 0%, rgba(10,132,255,0) 62%)",
            opacity: interpolate(frame, [0, 20], [0, 1], clamp),
            scale: interpolate(frame, [0, 2 * fps], [0.6, 1.1], { ...clamp, easing: outExpo }),
          }}
        />
        <Img
          name="App icon"
          src={staticFile("icon.png")}
          style={{
            position: "relative",
            width: 300,
            height: 300,
            filter: "drop-shadow(0 40px 80px rgba(0,0,0,0.55))",
            scale: interpolate(frame, [0, fps], [0.3, 1], {
              ...clamp,
              easing: Easing.spring({ damping: 11 }),
              output: "perceptual-scale",
            }),
            rotate: interpolate(frame, [0, fps], ["-18deg", "0deg"], { ...clamp, easing: Easing.spring({ damping: 13 }) }),
            opacity: interpolate(frame, [0, 6], [0, 1], clamp),
          }}
        />
      </div>
      <Interactive.Div
        name="App name"
        style={{
          fontFamily,
          fontSize: 150,
          fontWeight: 800,
          letterSpacing: -6,
          lineHeight: 1,
          paddingBottom: 10,
          background: "linear-gradient(100deg, #ffffff 0%, #9fd0ff 45%, #ffffff 55%, #ffffff 100%)",
          backgroundSize: "300% 100%",
          backgroundPosition: `${interpolate(frame, [20, 70], [100, 0], clamp)}% 0%`,
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          opacity: interpolate(frame, [10, 24], [0, 1], clamp),
          translate: interpolate(frame, [10, 34], ["0px 40px", "0px 0px"], { ...clamp, easing: outExpo }),
        }}
      >
        ClipNest
      </Interactive.Div>
      <Subtitle text={tagline} align="center" delay={20} size={44} />
      {footer ? (
        <div
          style={{
            marginTop: 20,
            display: "flex",
            gap: 26,
            alignItems: "center",
            opacity: interpolate(frame, [30, 46], [0, 1], clamp),
            translate: interpolate(frame, [30, 50], ["0px 30px", "0px 0px"], { ...clamp, easing: outExpo }),
          }}
        >
          <div
            style={{
              fontFamily,
              fontSize: 40,
              fontWeight: 700,
              color: "white",
              padding: "24px 50px",
              borderRadius: 999,
              background: "linear-gradient(180deg, #2E9BFF, #0A6CFF)",
              boxShadow: `0 18px 50px rgba(10,132,255,${interpolate(frame, [50, 70, 90, 110], [0.4, 0.8, 0.4, 0.8], clamp)}), inset 0 1px 0 rgba(255,255,255,0.35)`,
            }}
          >
            Download for Mac
          </div>
          <div style={{ fontFamily, fontSize: 36, fontWeight: 500, color: "rgba(235,235,245,0.75)" }}>{footer}</div>
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

/* ───────────── Text in screenshots: a scan line reads an image, then search finds a word in it ───────────── */

const ocrLines = [
  { text: "$ kubectl logs api-7f9c -n production", tone: "#8E8E93" },
  { text: "2026-11-22 03:12:04 INFO  listening on :8080", tone: "#D1D1D6" },
  { text: "2026-11-22 03:12:41 WARN  slow query 2.4s orders", tone: "#FFD60A" },
  { text: "2026-11-22 03:13:02 ERROR upstream timed out (110)", tone: "#FF6961" },
  { text: "2026-11-22 03:13:02 ERROR retry 3/3 payments-svc", tone: "#FF6961" },
];

const OcrSceneInner = ({ eyebrow, title, subtitle, accent, query }: Copy & { readonly query: string }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const scan = interpolate(frame, [20, 60], [0, 1], clamp);
  const found = frame > 66 + query.length * 3;
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 0,
          bottom: 0,
          width: 700,
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          gap: 28,
        }}
      >
        <Eyebrow text={eyebrow} accent={accent} />
        <Headline text={title} accent={accent} align="left" />
        <Subtitle text={subtitle} align="left" />
        <div style={{ marginTop: 8 }}>
          <TypingPill text={query} at={66} accent={accent} />
        </div>
      </div>
      <div style={{ position: "absolute", right: 110, top: 0, bottom: 0, display: "flex", alignItems: "center", perspective: 2200 }}>
        <div
          style={{
            width: 960,
            borderRadius: 28,
            overflow: "hidden",
            background: "#1c1c1e",
            boxShadow: `0 60px 140px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.14), 0 0 160px ${accent}40`,
            opacity: interpolate(frame, [6, 18], [0, 1], clamp),
            transform: `rotateY(${interpolate(frame, [6, 6 + 1.2 * fps], [-24, 0], { ...clamp, easing: Easing.spring({ damping: 200 }) })}deg)`,
            translate: interpolate(frame, [6, 6 + fps], ["120px 0px", "0px 0px"], { ...clamp, easing: Easing.spring({ damping: 200 }) }),
          }}
        >
          {/* Card header, as the panel shows an image clip */}
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "22px 30px", background: "linear-gradient(180deg, #ff6b81, #e8566c)" }}>
            <div style={{ fontFamily, color: "white" }}>
              <div style={{ fontSize: 34, fontWeight: 700 }}>Image</div>
              <div style={{ fontSize: 22, opacity: 0.85 }}>Screenshot · 2 min</div>
            </div>
            <div
              style={{
                fontFamily,
                fontSize: 22,
                fontWeight: 600,
                color: "white",
                padding: "10px 18px",
                borderRadius: 999,
                background: "rgba(0,0,0,0.25)",
                opacity: interpolate(frame, [60, 70], [0, 1], clamp),
              }}
            >
              ✓ Text recognised
            </div>
          </div>
          {/* The "screenshot": a terminal */}
          <div style={{ position: "relative", padding: "34px 34px 40px", background: "#0d0f14" }}>
            <div style={{ display: "flex", gap: 10, marginBottom: 24 }}>
              {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
                <div key={color} style={{ width: 16, height: 16, borderRadius: 8, background: color }} />
              ))}
            </div>
            {ocrLines.map((line, index) => {
              const lineY = (index + 0.5) / ocrLines.length;
              const read = scan > lineY;
              const match = line.text.indexOf(query);
              return (
                <div key={line.text} style={{ position: "relative", fontFamily: monoFamily, fontSize: 25, lineHeight: "54px", color: line.tone, whiteSpace: "pre" }}>
                  {match >= 0 ? (
                    <>
                      {line.text.slice(0, match)}
                      <span
                        style={{
                          background: found ? accent : "transparent",
                          color: found ? "#111" : line.tone,
                          borderRadius: 6,
                          boxShadow: found ? `0 0 30px ${accent}` : "none",
                        }}
                      >
                        {line.text.slice(match, match + query.length)}
                      </span>
                      {line.text.slice(match + query.length)}
                    </>
                  ) : (
                    line.text
                  )}
                  <div
                    style={{
                      position: "absolute",
                      inset: "6px -8px",
                      borderRadius: 8,
                      border: `2px solid ${accent}`,
                      opacity: read ? interpolate(frame, [60, 72], [0.9, 0], clamp) : 0,
                    }}
                  />
                </div>
              );
            })}
            {/* Scan line */}
            <div
              style={{
                position: "absolute",
                left: 0,
                right: 0,
                top: `${scan * 100}%`,
                height: 90,
                translate: "0px -90px",
                background: `linear-gradient(180deg, transparent, ${accent}55)`,
                borderBottom: `3px solid ${accent}`,
                opacity: interpolate(frame, [18, 22, 58, 64], [0, 1, 1, 0], clamp),
              }}
            />
          </div>
        </div>
      </div>
    </>
  );
};

export const OcrScene = Interactive.create({
  Component: OcrSceneInner,
  layout: "absolute-fill",
  schema: {
    ...textSchema,
    query: { type: "string", default: "timed out", description: "Word found in the screenshot" },
  },
});

/* ───────────── Transform: minified JSON → right-click → pretty JSON ───────────── */

const prettyLines: { readonly text: string; readonly color: string }[][] = [
  [{ text: "{", color: "#D1D1D6" }],
  [{ text: '  "service"', color: "#64D2FF" }, { text: ": ", color: "#D1D1D6" }, { text: '"api"', color: "#FF9F0A" }, { text: ",", color: "#D1D1D6" }],
  [{ text: '  "replicas"', color: "#64D2FF" }, { text: ": ", color: "#D1D1D6" }, { text: "3", color: "#BF5AF2" }, { text: ",", color: "#D1D1D6" }],
  [{ text: '  "env"', color: "#64D2FF" }, { text: ": ", color: "#D1D1D6" }, { text: '"production"', color: "#FF9F0A" }, { text: ",", color: "#D1D1D6" }],
  [{ text: '  "ports"', color: "#64D2FF" }, { text: ": [", color: "#D1D1D6" }, { text: "80", color: "#BF5AF2" }, { text: ", ", color: "#D1D1D6" }, { text: "443", color: "#BF5AF2" }, { text: "]", color: "#D1D1D6" }],
  [{ text: "}", color: "#D1D1D6" }],
];

const menuItems = ["Pretty JSON", "Minify JSON", "JSON → YAML", "Decode JWT", "Base64 decode", "URL decode", "Timestamp → date"];

const TransformSceneInner = ({ eyebrow, title, subtitle, accent }: Copy) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const menuIn = interpolate(frame, [28, 36], [0, 1], clamp);
  const menuOut = interpolate(frame, [62, 68], [1, 0], clamp);
  const pretty = interpolate(frame, [66, 78], [0, 1], clamp);
  const hover = Math.min(menuItems.length - 1, Math.max(0, Math.floor(interpolate(frame, [38, 54], [3, 0], clamp))));
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 0,
          bottom: 0,
          width: 660,
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          gap: 28,
        }}
      >
        <Eyebrow text={eyebrow} accent={accent} />
        <Headline text={title} accent={accent} align="left" />
        <Subtitle text={subtitle} align="left" />
      </div>
      <div style={{ position: "absolute", right: 110, top: 0, bottom: 0, width: 960, paddingLeft: 90, display: "flex", alignItems: "center" }}>
        <div
          style={{
            position: "relative",
            width: 640,
            borderRadius: 28,
            overflow: "hidden",
            background: "#1c1c1e",
            boxShadow: `0 60px 140px rgba(0,0,0,0.7), 0 0 0 ${interpolate(frame, [20, 26], [1, 5], clamp)}px ${frame > 20 ? accent : "rgba(255,255,255,0.14)"}, 0 0 160px ${accent}40`,
            opacity: interpolate(frame, [4, 16], [0, 1], clamp),
            translate: interpolate(frame, [4, 4 + fps], ["0px 120px", "0px 0px"], { ...clamp, easing: Easing.spring({ damping: 200 }) }),
          }}
        >
          <div style={{ padding: "22px 30px", background: "linear-gradient(180deg, #f2c94c, #e0b23a)" }}>
            <div style={{ fontFamily, fontSize: 34, fontWeight: 700, color: "white" }}>Text</div>
            <div style={{ fontFamily, fontSize: 22, color: "white", opacity: 0.85 }}>Grafana · just now</div>
          </div>
          <div style={{ position: "relative", height: 420, padding: 30 }}>
            <div
              style={{
                position: "absolute",
                inset: 30,
                fontFamily: monoFamily,
                fontSize: 26,
                lineHeight: 1.5,
                color: "#D1D1D6",
                wordBreak: "break-all",
                opacity: 1 - pretty,
              }}
            >
              {'{"service":"api","replicas":3,"env":"production","ports":[80,443]}'}
            </div>
            <div style={{ position: "absolute", inset: 30, opacity: pretty, translate: `0px ${(1 - pretty) * 20}px` }}>
              {prettyLines.map((line, index) => (
                <div key={index} style={{ fontFamily: monoFamily, fontSize: 30, lineHeight: 1.55, whiteSpace: "pre" }}>
                  {line.map((part, partIndex) => (
                    <span key={partIndex} style={{ color: part.color }}>
                      {part.text}
                    </span>
                  ))}
                </div>
              ))}
            </div>
          </div>
        </div>
        {/* Context menu */}
        <div
          style={{
            position: "absolute",
            left: 470,
            top: 330,
            width: 380,
            padding: 10,
            borderRadius: 18,
            background: "rgba(44,44,48,0.92)",
            border: "1px solid rgba(255,255,255,0.16)",
            boxShadow: "0 30px 80px rgba(0,0,0,0.6)",
            opacity: menuIn * menuOut,
            scale: interpolate(frame, [28, 38], [0.85, 1], { ...clamp, easing: Easing.spring({ damping: 14 }) }),
            transformOrigin: "0% 0%",
          }}
        >
          <div style={{ fontFamily, fontSize: 20, fontWeight: 600, color: "rgba(235,235,245,0.5)", padding: "8px 16px" }}>Transform</div>
          {menuItems.map((item, index) => (
            <div
              key={item}
              style={{
                fontFamily,
                fontSize: 26,
                color: "white",
                padding: "10px 16px",
                borderRadius: 10,
                background: index === hover ? accent : "transparent",
              }}
            >
              {item}
            </div>
          ))}
        </div>
      </div>
    </>
  );
};

export const TransformScene = Interactive.create({
  Component: TransformSceneInner,
  layout: "absolute-fill",
  schema: textSchema,
});

/* ───────────── Light and dark panel, wiped across ───────────── */

const GlassSceneInner = ({ eyebrow, title, subtitle, accent }: Copy) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const wipe = interpolate(frame, [30, 80], [100, 0], { ...clamp, easing: Easing.bezier(0.65, 0, 0.35, 1) });
  return (
    <>
      <div style={{ position: "absolute", top: 96, left: 100, right: 100, display: "flex", flexDirection: "column", alignItems: "center", gap: 22 }}>
        <Eyebrow text={eyebrow} accent={accent} />
        <Headline text={title} accent={accent} align="center" />
        <Subtitle text={subtitle} align="center" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 100,
          right: 100,
          bottom: 80,
          borderRadius: 34,
          overflow: "hidden",
          boxShadow: `0 60px 140px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.14), 0 0 160px ${accent}45`,
          opacity: interpolate(frame, [8, 20], [0, 1], clamp),
          translate: interpolate(frame, [8, 8 + fps], ["0px 160px", "0px 0px"], { ...clamp, easing: Easing.spring({ damping: 200 }) }),
        }}
      >
        <Img src={staticFile("panel.png")} style={{ width: "100%", display: "block" }} />
        <Img
          src={staticFile("panel-light.png")}
          style={{ position: "absolute", inset: 0, width: "100%", display: "block", clipPath: `inset(0 0 0 ${100 - wipe}%)` }}
        />
        <div
          style={{
            position: "absolute",
            top: 0,
            bottom: 0,
            left: `${100 - wipe}%`,
            width: 4,
            translate: "-2px 0px",
            background: "white",
            boxShadow: `0 0 30px 8px ${accent}`,
            opacity: wipe > 0.5 && wipe < 99.5 ? 1 : 0,
          }}
        />
      </div>
    </>
  );
};

export const GlassScene = Interactive.create({
  Component: GlassSceneInner,
  layout: "absolute-fill",
  schema: textSchema,
});

/* ───────────── Three small tools, fanned out like cards ───────────── */

const tools = [
  { image: "password.png", label: "Password generator", turn: -9, x: -560, delay: 14 },
  { image: "update.png", label: "Updates that install themselves", turn: 0, x: 0, delay: 8 },
  { image: "share.png", label: "Share as a link", turn: 9, x: 560, delay: 20 },
];

const ToolboxSceneInner = ({ eyebrow, title, accent }: Copy) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <>
      <div style={{ position: "absolute", top: 96, left: 100, right: 100, display: "flex", flexDirection: "column", alignItems: "center", gap: 22 }}>
        <Eyebrow text={eyebrow} accent={accent} />
        <Headline text={title} accent={accent} align="center" />
      </div>
      {tools.map((tool) => (
        <div
          key={tool.image}
          style={{
            position: "absolute",
            left: 960 + tool.x - 280,
            top: 430,
            width: 560,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 26,
            zIndex: tool.turn === 0 ? 2 : 1,
            opacity: interpolate(frame, [tool.delay, tool.delay + 10], [0, 1], clamp),
            translate: interpolate(frame, [tool.delay, tool.delay + fps], ["0px 260px", "0px 0px"], { ...clamp, easing: Easing.spring({ damping: 15 }) }),
            rotate: interpolate(frame, [tool.delay, tool.delay + fps], [`${tool.turn * 2.5}deg`, `${tool.turn}deg`], { ...clamp, easing: Easing.spring({ damping: 15 }) }),
          }}
        >
          <div
            style={{
              width: 560,
              borderRadius: 24,
              overflow: "hidden",
              boxShadow: `0 50px 120px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.14), 0 0 100px ${accent}35`,
            }}
          >
            <Img src={staticFile(tool.image)} style={{ width: "100%", display: "block" }} />
          </div>
          <div style={{ fontFamily, fontSize: 34, fontWeight: 600, color: "white", textAlign: "center" }}>{tool.label}</div>
        </div>
      ))}
    </>
  );
};

export const ToolboxScene = Interactive.create({
  Component: ToolboxSceneInner,
  layout: "absolute-fill",
  schema: textSchema,
});

/* ───────────── "And so much more": a grid of everything else ───────────── */

const extras = [
  ["📌", "Pinboards"],
  ["🔗", "Auto Links board"],
  ["🌐", "IP & CIDR board"],
  ["⌘", "⌘1–9 quick paste"],
  ["🎨", "Colours & files"],
  ["📝", "Rich text"],
  ["👁", "Reveal for 15 s"],
  ["🔐", "Ansible Vault masked"],
  ["🧾", "PLAY RECAP reader"],
  ["🔁", "Retry failed hosts"],
  ["🪪", "JWT decoder"],
  ["🧬", "JSON ⇄ YAML"],
  ["🇻🇳", "Vietnamese OCR"],
  ["🚫", "Ignore apps"],
  ["📊", "Built-in benchmark"],
  ["💾", "SQLite, on your Mac"],
];

const GridSceneInner = ({ eyebrow, title, accent }: Copy) => {
  const frame = useCurrentFrame();
  return (
    <>
      <div style={{ position: "absolute", top: 90, left: 100, right: 100, display: "flex", flexDirection: "column", alignItems: "center", gap: 18 }}>
        <Eyebrow text={eyebrow} accent={accent} />
        <Headline text={title} accent={accent} align="center" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 130,
          right: 130,
          top: 400,
          display: "grid",
          gridTemplateColumns: "repeat(4, 1fr)",
          gap: 26,
        }}
      >
        {extras.map(([icon, label], index) => {
          const at = 16 + (index % 4) * 3 + Math.floor(index / 4) * 6;
          return (
            <div
              key={label}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 20,
                padding: "26px 28px",
                borderRadius: 26,
                background: "linear-gradient(180deg, rgba(255,255,255,0.11), rgba(255,255,255,0.04))",
                border: "1px solid rgba(255,255,255,0.14)",
                boxShadow: "0 20px 50px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.12)",
                opacity: interpolate(frame, [at, at + 8], [0, 1], clamp),
                scale: interpolate(frame, [at, at + 16], [0.7, 1], { ...clamp, easing: Easing.spring({ damping: 12 }) }),
                translate: interpolate(frame, [at, at + 16], ["0px 40px", "0px 0px"], { ...clamp, easing: outExpo }),
              }}
            >
              <div
                style={{
                  width: 64,
                  height: 64,
                  borderRadius: 18,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 34,
                  fontFamily,
                  fontWeight: 700,
                  color: "white",
                  background: `${accent}30`,
                }}
              >
                {icon}
              </div>
              <div style={{ fontFamily, fontSize: 32, fontWeight: 600, color: "white" }}>{label}</div>
            </div>
          );
        })}
      </div>
    </>
  );
};

export const GridScene = Interactive.create({
  Component: GridSceneInner,
  layout: "absolute-fill",
  schema: textSchema,
});
