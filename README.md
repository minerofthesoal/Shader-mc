# HyperRealistic Shaders

A hyper-realistic shader pack for **Minecraft Java Edition 1.21.9 - 1.21.11**.
Requires [OptiFine](https://optifine.net) or [Iris](https://irisshaders.dev) (Fabric/Quilt).

## Features

| Feature | Description |
|---------|-------------|
| **ACES Tone Mapping** | Filmic color grading with adjustable exposure, saturation, and color temperature |
| **Shadow Mapping** | PCF soft shadows with configurable resolution (512-4096) and distance |
| **Sun God Rays** | Volumetric light shaft scattering from the sun |
| **Screen-Space Ray Tracing** | Reflections on water and wet surfaces (toggleable) |
| **HDR Bloom** | Gaussian-blurred glow on bright/emissive surfaces |
| **Water Effects** | Gerstner waves, animated caustics, specular highlights, foam, fresnel reflections |
| **Dynamic Lighting** | Colored light from torches (warm), lava (orange), glowstone (yellow) |
| **Volumetric Fog** | Height-based fog denser in valleys, animated with noise |
| **Subsurface Scattering** | Light transmission through leaves and grass (backlit glow) |
| **Aurora Borealis** | Animated northern lights curtains at night (green/cyan/purple) |
| **Volumetric Clouds** | FBM noise-based clouds with sun lighting and weather reactivity |
| **True Dark Mode** | Optional pitch-black caves and nights |
| **Night Eye Adaptation** | Blue shift and brightness adaptation in darkness |
| **Waving Plants** | Wind-animated grass, leaves, flowers, crops, and vines |
| **Vignette & Chromatic Aberration** | Cinematic screen effects |

## Quality Presets

All features are toggleable in-game via **Shader Options** menu:

| Preset | Shadows | Bloom | God Rays | SSR | Volumetric | Performance |
|--------|:-------:|:-----:|:--------:|:---:|:----------:|:-----------:|
| **Low** | 1024 | Off | Off | Off | Off | Best |
| **Medium** | 1024 | On | On | Off | On | Good |
| **High** (default) | 2048 | On | On | On | On | Moderate |
| **Ultra** | 4096 | On | On | On | On | Demanding |

## Installation

1. Install [OptiFine](https://optifine.net) or [Iris](https://irisshaders.dev) + Fabric
2. Download the `.zip` from [Releases](../../releases)
3. Place in `.minecraft/shaderpacks/`
4. In-game: **Options > Video Settings > Shaders** > select the pack
5. Click **Shader Options** to customize features

## Building from Source

```bash
bash scripts/build.sh 1.21.11
# Output: build/HyperRealistic-Shaders-v1.21.11.zip
```

## Shader Architecture

```
shaders/
├── gbuffers_terrain.vsh/fsh    # Block/terrain geometry pass
├── gbuffers_water.vsh/fsh      # Water geometry with wave animation
├── gbuffers_entities.vsh/fsh   # Entity rendering
├── gbuffers_hand.vsh/fsh       # First-person hand
├── gbuffers_skybasic.vsh/fsh   # Sky atmosphere, stars, aurora
├── gbuffers_skytextured.vsh/fsh # Sun/moon with corona
├── gbuffers_textured*.vsh/fsh  # Particles and misc geometry
├── gbuffers_weather.vsh/fsh    # Rain/snow particles
├── shadow.vsh/fsh              # Shadow map rendering
├── composite.vsh/fsh           # Shadow application, lighting, god rays, fog
├── composite1.vsh/fsh          # SSR reflections, bloom blur
├── composite2.vsh/fsh          # Bloom combine, night eye
├── final.vsh/fsh               # Tone mapping, color grading, vignette
├── shaders.properties          # Configuration and options
└── lang/en_US.lang             # Option descriptions
```

## Compatibility

- Minecraft Java Edition 1.21.9, 1.21.10, 1.21.11
- OptiFine (any recent version)
- Iris 1.7+ (Fabric/Quilt)
- OpenGL 2.1+ (GLSL 120)

## License

See [LICENSE](LICENSE) for details.
