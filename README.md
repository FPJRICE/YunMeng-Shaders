# YunMeng Shaders

云梦光影 is a Minecraft shader pack with two visual styles. **Guofeng Ink** uses soft jade and ink colors, outlines, and paper texture. **Xianxia Mist** uses richer colors, luminous skies, celestial details, and clear water.

The current release is **0.1.0-alpha.5**. This alpha refines clouds, weather fog, atmospheric and underwater light shafts, water reflections, and both illustrated suns. Compilation and controlled rendering checks have passed; broader in-game Iris compatibility and regression testing remain in progress.

## Features

- Dynamic skies, distinct volumetric cloud formations for both styles, valley mist, moon phases, and auroras
- Illustrated suns with soft sky blending and gently animated glow, with a larger sun for Guofeng Ink
- Atmospheric rain and snow, coordinated storm lighting, weather-aware border fog, and cloud-controlled directional illumination
- Lighting, shadows, light shafts, and wind-animated foliage
- Water waves, depth-tinted transparency, sky/cloud and object reflections, foam, caustics, and underwater atmosphere with cloud-controlled light shafts
- View-dependent sun lens flare and atmospheric light shafts through openings and glass windows, with separate atmospheric strength control
- Spatial or temporal anti-aliasing, with camera and foliage motion blur and estimated entity motion in Smooth mode
- Low, Medium, High, and Ultra quality presets with separate style and effect controls

The defaults are Medium quality, Subtle anti-aliasing, Fast motion blur at 0.50 strength, and Soft sun lens flare.

## Install

Use `YunMeng_Shaders_0.1.0-alpha.5.zip` for this release. Place the ZIP in your Minecraft profile's `shaderpacks` folder and select it with Iris. GitHub's automatic source archive is for source browsing, not installation. Use the Minecraft compatibility versions listed on the download page; the alpha build number is the shader pack version.

## Alpha limitations

Cloud lighting and underwater light paths use approximations. Near-water transitions, weather changes, and performance still need broader in-game testing across scenes and hardware. Minecraft and Iris version compatibility should be verified before adding download-page compatibility tags.

## Source layout

- `shaders/` contains GLSL programs, settings, translations, and textures.
- `tools/generate_cloud_volume.py` regenerates the cloud density atlas using Python, NumPy, and Pillow. Development tools stay in the source repository and are excluded from installable ZIPs; the generated textures are included.
- `CHANGELOG.txt` describes the current build.
- `LICENSE.txt`, `COPYING`, and `THIRD_PARTY_NOTICES.txt` contain the license terms and required credits.

## License and texture reuse

Original YunMeng shader code and textures are licensed under **GPL-3.0-only**. You may reuse and modify them under GPLv3, including commercially, while preserving copyright, license, and attribution notices. Third-party material retains the terms and credits listed in `THIRD_PARTY_NOTICES.txt`. See `LICENSE.txt` and `COPYING` for the full terms.
