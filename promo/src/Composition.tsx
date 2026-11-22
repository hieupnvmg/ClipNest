import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { AbsoluteFill } from "remotion";
import { Backdrop } from "./Backdrop";
import { Brand, SplitFeature, WideFeature } from "./Scenes";

export const ClipNestPromo = () => {
  return (
    <AbsoluteFill>
      <Backdrop />
      <TransitionSeries>
        <TransitionSeries.Sequence name="Intro" durationInFrames={84}>
          <Brand
            name="Intro card"
            tagline={"Everything you copy, one keystroke away."}
            footer=""
            style={{ justifyContent: "center", alignItems: "center" }}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />
        <TransitionSeries.Sequence name="Shortcut" durationInFrames={120}>
          <WideFeature
            name="Shortcut scene"
            keys="⇧ ⌘ V"
            eyebrow="Open"
            title="Your whole clipboard."
            subtitle="Text, links, images, files and colours — all in one glassy panel."
            accent="#0A84FF"
            image="panel.png"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={slide({ direction: "from-right" })}
          timing={linearTiming({ durationInFrames: 14 })}
        />
        <TransitionSeries.Sequence name="Search" durationInFrames={105}>
          <SplitFeature
            name="Search scene"
            eyebrow="Instant search"
            title={"Type. Find.\nPaste."}
            subtitle={"Every keystroke narrows the results — no lag, even with huge clips."}
            accent="#FFD60A"
            image="search.png"
            imageWidth={900}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={slide({ direction: "from-right" })}
          timing={linearTiming({ durationInFrames: 14 })}
        />
        <TransitionSeries.Sequence name="Privacy" durationInFrames={105}>
          <WideFeature
            name="Privacy scene"
            keys=""
            eyebrow="Private by default"
            title="Secrets stay hidden."
            subtitle="Passwords, tokens, cards and phone numbers are masked — even in screenshots."
            accent="#30D158"
            image="privacy.png"
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />
        <TransitionSeries.Sequence name="DevOps" durationInFrames={120}>
          <SplitFeature
            name="DevOps scene"
            eyebrow="For SRE & DevOps"
            title={"Think before\nyou paste."}
            subtitle={"Ansible commands that hit production get a review sheet first — with a one-click dry run."}
            accent="#FF9F0A"
            image="paste-review.png"
            imageWidth={900}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={slide({ direction: "from-bottom" })}
          timing={linearTiming({ durationInFrames: 14 })}
        />
        <TransitionSeries.Sequence name="Sync" durationInFrames={105}>
          <SplitFeature
            name="Sync scene"
            eyebrow="iCloud Sync"
            title={"Every Mac.\nEncrypted."}
            subtitle={"Pinboards sync through iCloud Drive with a passphrase only you know."}
            accent="#64D2FF"
            image="sync.png"
            imageWidth={860}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={slide({ direction: "from-bottom" })}
          timing={linearTiming({ durationInFrames: 14 })}
        />
        <TransitionSeries.Sequence name="Speed" durationInFrames={105}>
          <SplitFeature
            name="Speed scene"
            eyebrow="Fast, and measured"
            title={"Faster than\na frame."}
            subtitle={"Every save takes a few milliseconds. Check it yourself in Settings."}
            accent="#BF5AF2"
            image="benchmark.png"
            imageWidth={860}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: 14 })} />
        <TransitionSeries.Sequence name="Outro" durationInFrames={120}>
          <Brand
            name="Outro card"
            tagline={"Free · No account · Everything stays on your Mac."}
            footer="github.com/hieupnvmg/ClipNest"
            style={{ justifyContent: "center", alignItems: "center" }}
          />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </AbsoluteFill>
  );
};
