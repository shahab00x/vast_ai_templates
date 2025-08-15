#!/bin/bash

# Modified A1111 provisioning script to download Flux-Kontext assets
# (UNet, VAE, and text encoders). Supports HF_TOKEN/CIVITAI_TOKEN headers.
# Note: A1111 cannot use Flux models. This stages assets under A1111 tree
# for persistence; use ComfyUI/Flux-capable tools to consume them.

source /venv/main/bin/activate
A1111_DIR=${WORKSPACE}/stable-diffusion-webui

APT_PACKAGES=()
PIP_PACKAGES=()

# Leave standard SD downloads empty; focus on Flux assets
CHECKPOINT_MODELS=()
UNET_MODELS=()
LORA_MODELS=()
VAE_MODELS=()
ESRGAN_MODELS=()
CONTROLNET_MODELS=()
EXTENSIONS=()

# Flux-Kontext components (download-only)
FLUX_UNET_MODELS=(
  "https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/resolve/main/flux-kontext-dev.safetensors"
)
FLUX_VAE_MODELS=(
  "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors"
)
FLUX_CLIP_MODELS=(
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
  provisioning_print_header
  provisioning_get_apt_packages
  provisioning_get_extensions
  provisioning_get_pip_packages

  provisioning_get_files \
    "${A1111_DIR}/models/Stable-diffusion" \
    "${CHECKPOINT_MODELS[@]}"

  provisioning_get_files \
    "${A1111_DIR}/models/unet" \
    "${FLUX_UNET_MODELS[@]}"

  provisioning_get_files \
    "${A1111_DIR}/models/vae" \
    "${FLUX_VAE_MODELS[@]}"

  provisioning_get_files \
    "${A1111_DIR}/models/clip" \
    "${FLUX_CLIP_MODELS[@]}"

  # Avoid git errors because we run as root but files are owned by 'user'
  export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
  git config --file $GIT_CONFIG_GLOBAL --add safe.directory '*'

  # Start and exit because webui will probably require a restart
  cd "${A1111_DIR}"
  LD_PRELOAD=libtcmalloc_minimal.so.4 \
    python launch.py \
      --skip-python-version-check \
      --no-download-sd-model \
      --do-not-download-clip \
      --no-half \
      --port 11404 \
      --exit

  provisioning_print_end
}

function provisioning_get_apt_packages() {
  if [[ -n $APT_PACKAGES ]]; then
    sudo $APT_INSTALL ${APT_PACKAGES[@]}
  fi
}

function provisioning_get_pip_packages() {
  if [[ -n $PIP_PACKAGES ]]; then
    pip install --no-cache-dir ${PIP_PACKAGES[@]}
  fi
}

function provisioning_get_extensions() {
  for repo in "${EXTENSIONS[@]}"; do
    dir="${repo##*/}"
    path="${A1111_DIR}/extensions/${dir}"
    if [[ ! -d $path ]]; then
      printf "Downloading extension: %s...\n" "${repo}"
      git clone "${repo}" "${path}" --recursive
    fi
  done
}

function provisioning_get_files() {
  if [[ -z $2 ]]; then return 1; fi
  dir="$1"
  mkdir -p "$dir"
  shift
  arr=("$@")
  printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
  for url in "${arr[@]}"; do
    printf "Downloading: %s\n" "${url}"
    provisioning_download "${url}" "${dir}"
    printf "\n"
  done
}

function provisioning_print_header() {
  printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
  printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
  [[ -n "$HF_TOKEN" ]] || return 1
  url="https://huggingface.co/api/whoami-v2"
  response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
    -H "Authorization: Bearer $HF_TOKEN" \
    -H "Content-Type: application/json")
  [[ "$response" -eq 200 ]]
}

function provisioning_has_valid_civitai_token() {
  [[ -n "$CIVITAI_TOKEN" ]] || return 1
  url="https://civitai.com/api/v1/models?hidden=1&limit=1"
  response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
    -H "Authorization: Bearer $CIVITAI_TOKEN" \
    -H "Content-Type: application/json")
  [[ "$response" -eq 200 ]]
}

# Download from $1 URL to $2 dir path
function provisioning_download() {
  if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
    auth_token="$HF_TOKEN"
  elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
    auth_token="$CIVITAI_TOKEN"
  fi
  if [[ -n $auth_token ]]; then
    wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
  else
    wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
  fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
  provisioning_start
fi
