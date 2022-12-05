#!/bin/zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

set -xeo pipefail
conda activate coreml_stable_diffusion

DESTINATION="$1"

if [[ -z "$DESTINATION" ]] ; then
  echo "Usage: build-models ./build"
  exit 1
fi

build() {
  local model_version
  model_version="$1"
  local dest
  dest="$2"
  mkdir -p "$DESTINATION"
  python -m python_coreml_stable_diffusion.torch2coreml \
    --convert-unet --convert-text-encoder --convert-vae-decoder --convert-safety-checker \
    --model-version "$model_version" \
    --bundle-resources-for-swift-cli \
    --chunk-unet \
    -o "../$DESTINATION/$dest"
}

cd ml-stable-diffusion
build stabilityai/stable-diffusion-2-base sd2-base
build CompVis/stable-diffusion-v1-4       sd1.4
build runwayml/stable-diffusion-v1-5      sd1.5
