# Gauss

A Stable Diffusion app for macOS built with SwiftUI and Apple's [ml-stable-diffusion](https://github.com/apple/ml-stable-diffusion) CoreML models.

![Screenshot](./screenshot.png)

## Usage

- Write prompt text and adjust parameters in the composer view at the bottom.
- To export an image, just drag it to Finder or any other image editor.
- You can always generate more images from an existing prompt.

## Project Status

**This software is under development and is pre-alpha quality; there is no release for end-users yet.** If you'd like to contribute, you can build the project by following the instructions for developers below.

See [DiffusionBee](https://github.com/divamgupta/diffusionbee-stable-diffusion-ui) for a Stable Diffusion UI built with Electron & Python, but that works out of the box today.

## System requirements

- macOS 13.1+
- Recommended: an Apple Silicon CPU. Intel hardware may work, but is untested by the primary developer and could be slow.

## Developer setup

### System requirements

- macOS 13.1+
- Xcode 14.2+
- `git-lfs` is used to fetch pre-built models from HuggingFace.
  - If you have `brew`: `brew install git-lfs`, then `git lfs install`.
  - Otherwise, [download the installer here](https://git-lfs.com/), then `git lfs install`.
- At least 10gb of free disk space.
- Recommended: [set up Xcode to format code when you save](https://luisramos.dev/xcode-format-and-save).

### Building from source

1. Clone this repo.
1. Run `make -j 4`. This will download pre-build models from HuggingFace.
1. Open the project file (Gauss.xcodeproj) with Xcode.
1. You should be able to build (Cmd-B) and run the project.
