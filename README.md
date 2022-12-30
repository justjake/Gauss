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

1. Clone this repo: `git clone https://github.com/justjake/Gauss`
1. Inside the repo, run `make`. This will download pre-build models from HuggingFace into `./compiled-models`. You can run `make -j 3` to download the models in parallel if you have a fast connetion. Eg: `cd Gauss && make`
1. Open the project file (Gauss.xcodeproj) with Xcode: `open Gauss.xcodeproj`
1. You should be able to build (Cmd-B) and run the project.

### Packing zip files for release

The current plan for releasing Gauss is to pack the models it needs into zips, split the zips into parts no larger than 2gb, and then publish everything via Github release. 2gb is the [file size limit for Github releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#:~:text=Each%20file%20included%20in%20a,a%20release%2C%20nor%20bandwidth%20usage.).

We'll teach Gauss itself how to find, download, and re-assemble the zip files from Github directly.

To create the zip files: `make zips`

### Publishing releases to Github

TODO - figure this out!
