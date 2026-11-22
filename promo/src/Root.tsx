import { Composition } from "remotion";
import { ClipNestPromo } from "./Composition";

// 1,585 frames of scenes minus 6 fades × 14 and 7 slides × 16 = 1,389 frames (about 46 s).
export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="ClipNestPromo"
        component={ClipNestPromo}
        durationInFrames={1389}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
