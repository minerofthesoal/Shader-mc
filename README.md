# HyperRealistic Shaders

A hyper-realistic shader pack for **Minecraft Bedrock Edition 1.21.9 - 1.21.11**.

## Features

| Feature | Description |
|---------|-------------|
| **ACES Tone Mapping** | Filmic color grading with exposure, saturation, and vibrance controls |
| **Sun God Rays** | Volumetric light shaft scattering from the sun |
| **Toggleable Ray Tracing** | Screen-space reflections for water and wet surfaces |
| **Bloom** | HDR bright-pass glow on emissive and bright surfaces |
| **Water Effects** | Animated waves, caustics, specular highlights, foam, fresnel reflections |
| **Dynamic Lighting** | Colored light from torches (warm), lava (orange), glowstone (yellow) |
| **Dynamic Shadows** | Sun-angle shadows with ambient occlusion and contact darkening |
| **True Dark Mode** | Optional pitch-black caves and nights for survival horror gameplay |
| **Atmospheric Sky** | Rayleigh/Mie scattering, procedural stars, moon glow, cloud wisps |

## Variants

| Variant | Ray Tracing | True Dark | Bloom | God Rays | Shadow Quality |
|---------|:-----------:|:---------:|:-----:|:--------:|:--------------:|
| **Full** (default) | On | Off | On | On | Medium |
| **Standard** | Off | Off | On | On | Medium |
| **True Dark** | Off | On | On | On | Medium |
| **Ultra** | On | On | On | On | High |
| **Lite** | Off | Off | Off | Off | Low |

## Installation

1. Download the `.mcpack` file for your Minecraft version
2. Double-click to import, or go to **Settings > Storage > Import** in Minecraft
3. Activate the pack in your world's **Resource Packs** settings
4. Choose a subpack preset in the pack's gear/settings icon

## Building from Source

```bash
# Build for 1.21.11
bash scripts/build.sh 1.21.11

# Build for 1.21.9
bash scripts/build.sh 1.21.9

# Output: build/*.mcpack
```

## Compatibility

- Minecraft Bedrock Edition 1.21.9, 1.21.10, 1.21.11
- Windows 10/11, Android, iOS, Xbox, PlayStation, Nintendo Switch

## CI/CD

GitHub Actions workflows automatically build and create releases:
- `build-1.21.11.yml` - Builds and releases for MC 1.21.11
- `build-1.21.9-10.yml` - Builds and releases for MC 1.21.9 and 1.21.10

## License

See [LICENSE](LICENSE) for details.
