import { Composition } from "remotion";
import { ClipNestPromo } from "./Composition";

// 864 frames of scenes minus 7 transitions × 14 frames = 766 frames (about 25.5 s).
export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="ClipNestPromo"
        component={ClipNestPromo}
        durationInFrames={766}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
