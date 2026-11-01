# Swift Music launcher icon

Generated with the built-in `image_gen` tool. Master artwork: `swift_music_icon.png`.

Style reference: high-contrast green, black and white circular music identity from [JOOX official brand guidelines](https://designer.tencent.co.th/logo/joox.html). Swift Music uses its own white S/lightning ribbon symbol. The master is full bleed, without baked-in rounded corners; native launcher masks provide the final shape.

## Final generation prompt

```text
Use case: logo-brand.
Asset type: production mobile launcher icon for the music player "Swift Music", iOS and Android.
Create one clean, premium, flat graphic app icon. Full-bleed perfectly uniform vivid emerald green background (#1ED760), square 1024x1024 canvas. In the exact center, a bold near-black vinyl-disc circle occupying about 70% of the image width. Inside that disc, a single very bold white, flowing lightning/play ribbon that suggests an abstract S and fast music playback. The white symbol should be instantly readable at 48px, with generous simple shapes and smooth geometric edges. Slight forward motion in the white ribbon, balanced optical centering.
Style direction: the high-contrast green/black/white, bold circular music-symbol feel of JOOX, but an original Swift Music mark: use the distinctive S/lightning/play ribbon, not the JOOX white circle/dot speech-bubble mark.
Composition: large symbol, even margins, carefully centered, comfortably contained. Background reaches all four canvas edges. The icon artwork itself is a full square; the OS will apply corner rounding.
Constraints: exactly one icon, no app mockup, no phone, no tiled variants, no lettering, no words, no brand names, no watermark, no exterior frame, no rounded-square tile inside the canvas, no outer white border, no shadows, no gradients, no texture, no 3D effects. Opaque green background.
```

## Packaging

Run `dart run flutter_launcher_icons` after `flutter pub get`. Configuration is in `flutter_launcher_icons.yaml`. Android adaptive foreground uses a safe inset to preserve the complete symbol across circle and rounded-square masks. iOS assets have their alpha removed for App Store icon compatibility.
