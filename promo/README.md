# ClipNest promo video

The 25-second video at the top of the main README, built with [Remotion](https://www.remotion.dev).
The screenshots in `public/` are rendered by the app itself (`ClipNest --render-preview … --dark-preview`), so the video always shows the real UI.

```bash
npm install
npx remotion studio                 # preview and edit
npx remotion render ClipNestPromo out/clipnest-promo.mp4 --codec=h264 --crf=20
```

To refresh the README copies:

```bash
cp out/clipnest-promo.mp4 ../docs/promo.mp4
mkdir -p out/frames && ffmpeg -i out/clipnest-promo.mp4 -vf "fps=15,scale=1200:-1" out/frames/f%04d.png
img2webp -loop 0 -d 67 -lossy -q 70 -m 4 -mixed out/frames/f*.png -o ../docs/promo.webp
```

- `src/Composition.tsx` — the scene order, copy and transitions
- `src/Scenes.tsx` — the intro/outro card and the two feature layouts
- `src/Backdrop.tsx` — the drifting glow behind every scene
