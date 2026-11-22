import { loadFont } from "@remotion/google-fonts/Inter";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";

export const { fontFamily } = loadFont("normal", {
  weights: ["400", "500", "600", "700", "800"],
  subsets: ["latin", "latin-ext", "vietnamese"],
});

export const { fontFamily: monoFamily } = loadMono("normal", {
  weights: ["400", "600"],
  subsets: ["latin"],
});
