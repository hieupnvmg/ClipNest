import { linearTiming, springTiming, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { AbsoluteFill } from "remotion";
import { Backdrop } from "./Backdrop";
import { Brand, GlassScene, GridScene, OcrScene, SplitFeature, ToolboxScene, TransformScene, WideFeature } from "./Scenes";

export const ClipNestPromo = () => {
  return (
    <AbsoluteFill>
      <Backdrop />
      <TransitionSeries>
        <TransitionSeries.Sequence name="Intro" durationInFrames={90}>
          <Brand
            name="Intro card"
            tagline="Everything you copy, one keystroke away."
            footer=""
            style={{ justifyContent: "center", alignItems: "center" }}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />

        <TransitionSeries.Sequence name="Shortcut" durationInFrames={115}>
          <WideFeature
            name="Shortcut scene"
            keys="⇧ ⌘ V"
            eyebrow="Open"
            title={"Your whole clipboard.\nOne panel."}
            subtitle=""
            accent="#0A84FF"
            image="panel.png"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-right" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="Search" durationInFrames={105}>
          <SplitFeature
            name="Search scene"
            eyebrow="Instant search"
            title={"Type. Find.\nPaste."}
            subtitle="Every keystroke narrows the results — no lag, even with huge clips."
            accent="#FFD60A"
            image="search.png"
            imageWidth={900}
            typed="nginx"
            chips=""
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-right" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="Text in images" durationInFrames={125}>
          <OcrScene
            name="OCR scene"
            eyebrow="Text in screenshots"
            title={"Search inside\nyour screenshots."}
            subtitle="Apple Vision reads every image — on your Mac, in English and Vietnamese."
            accent="#FF6B81"
            query="timed out"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />

        <TransitionSeries.Sequence name="Privacy" durationInFrames={110}>
          <WideFeature
            name="Privacy scene"
            keys=""
            eyebrow="Private by default"
            title={"Secrets stay\nhidden."}
            subtitle=""
            accent="#30D158"
            image="privacy.png"
            spots={[
              { x: 0.012, y: 0.18, w: 0.172, h: 0.725, at: 40 },
              { x: 0.192, y: 0.18, w: 0.172, h: 0.725, at: 46 },
              { x: 0.372, y: 0.18, w: 0.172, h: 0.725, at: 52 },
            ]}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-bottom" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="DevOps" durationInFrames={115}>
          <SplitFeature
            name="DevOps scene"
            eyebrow="For SRE & DevOps"
            title={"Think before\nyou paste."}
            subtitle="Production Ansible commands get a review sheet first — with a one-click dry run."
            accent="#FF9F0A"
            image="paste-review.png"
            imageWidth={900}
            typed=""
            chips="no --limit, no --check, secret in -e"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-right" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="Ansible" durationInFrames={110}>
          <WideFeature
            name="Ansible scene"
            keys=""
            eyebrow="Reads your output"
            title={"Ansible,\nexplained."}
            subtitle=""
            accent="#FF9F0A"
            image="devtools.png"
            spots={[
              { x: 0.012, y: 0.18, w: 0.172, h: 0.725, at: 40 },
              { x: 0.192, y: 0.18, w: 0.172, h: 0.725, at: 48 },
              { x: 0.372, y: 0.18, w: 0.172, h: 0.725, at: 56 },
            ]}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-right" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="Transforms" durationInFrames={120}>
          <TransformScene
            name="Transform scene"
            eyebrow="Right-click transforms"
            title={"Messy in.\nClean out."}
            subtitle="Pretty or minify JSON, convert to YAML, decode JWT, Base64, URLs and timestamps."
            accent="#BF5AF2"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />

        <TransitionSeries.Sequence name="Liquid Glass" durationInFrames={110}>
          <GlassScene
            name="Glass scene"
            eyebrow="Liquid Glass"
            title={"Light or dark.\nAlways at home."}
            subtitle=""
            accent="#64D2FF"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-bottom" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="Sync" durationInFrames={105}>
          <SplitFeature
            name="Sync scene"
            eyebrow="iCloud Sync"
            title={"Every Mac.\nEncrypted."}
            subtitle="Pinboards sync through iCloud Drive with a passphrase only you know. No account, no server."
            accent="#64D2FF"
            image="sync.png"
            imageWidth={860}
            typed=""
            chips="AES-GCM, PBKDF2 600k"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={slide({ direction: "from-right" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 16 })} />

        <TransitionSeries.Sequence name="Toolbox" durationInFrames={115}>
          <ToolboxScene name="Toolbox scene" eyebrow="Built in" title="Little tools, ready when you are." subtitle="" accent="#0A84FF" />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />

        <TransitionSeries.Sequence name="Speed" durationInFrames={105}>
          <SplitFeature
            name="Speed scene"
            eyebrow="Fast, and measured"
            title={"Faster than\na frame."}
            subtitle="Every save takes a few milliseconds. Check it yourself in Settings."
            accent="#30D158"
            image="benchmark.png"
            imageWidth={820}
            typed=""
            chips="1–4 ms saves, ~50 ms launch"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />

        <TransitionSeries.Sequence name="And more" durationInFrames={130}>
          <GridScene name="Grid scene" eyebrow="And so much more" title="Made for people who copy a lot." subtitle="" accent="#0A84FF" />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />

        <TransitionSeries.Sequence name="Outro" durationInFrames={130}>
          <Brand
            name="Outro card"
            tagline="Free · No account · Everything stays on your Mac."
            footer="github.com/hieupnvmg/ClipNest"
            style={{ justifyContent: "center", alignItems: "center" }}
          />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </AbsoluteFill>
  );
};
