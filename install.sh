#!/usr/bin/env bash
# Instalador do "IA local para OpenCode" (llama.cpp + Vulkan).
#
#   ./install.sh                 # tudo: binarios, 3 modelos, servicos, config
#   ./install.sh --sem-modelos   # nao baixa os modelos (12 GB)
#   ./install.sh --sem-servicos  # nao habilita o systemd
#
# Testado em Zorin OS / Ubuntu 24.04+ com GPU AMD Polaris (RX 580).
# Funciona em qualquer GPU com Vulkan (RADV/ANV/NVK) — apenas ajuste --n-cpu-moe
# se a sua VRAM nao for 8 GB.
set -euo pipefail

LLAMA_VERSION="${LLAMA_VERSION:-b11998}"
ROOT="$HOME/.local/share/llama.cpp"
MODELS="$HOME/Modelos"
BIN="$HOME/.local/bin"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BAIXAR_MODELOS=1
HABILITAR_SERVICOS=1
for arg in "$@"; do
  case "$arg" in
    --sem-modelos)  BAIXAR_MODELOS=0 ;;
    --sem-servicos) HABILITAR_SERVICOS=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "nao rode como root (o script usa \$HOME)"
for c in curl tar awk; do command -v "$c" >/dev/null || die "falta o comando '$c'"; done

case "$(uname -m)" in
  x86_64)  ARCH=x64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "arquitetura $(uname -m) sem build oficial do llama.cpp" ;;
esac

# ---------------------------------------------------------------- Vulkan
log "verificando Vulkan"
if command -v vulkaninfo >/dev/null; then
  GPU=$(vulkaninfo --summary 2>/dev/null | grep -m1 -oE 'deviceName *= *.*' | sed 's/.*= *//' || true)
  if [ -n "$GPU" ]; then ok "GPU Vulkan: $GPU"
  else warn "vulkaninfo nao listou GPU. Instale: sudo apt install mesa-vulkan-drivers vulkan-tools"; fi
else
  warn "vulkaninfo nao instalado. Instale: sudo apt install mesa-vulkan-drivers vulkan-tools"
fi

# ------------------------------------------------------------- llama.cpp
mkdir -p "$ROOT/releases" "$ROOT/logs" "$ROOT/run" "$MODELS" "$BIN"
TARBALL="llama-${LLAMA_VERSION}-bin-ubuntu-vulkan-${ARCH}.tar.gz"
DEST="$ROOT/vulkan-${LLAMA_VERSION}"

if [ -x "$DEST/llama-server" ]; then
  ok "llama.cpp $LLAMA_VERSION ja instalado"
else
  log "baixando llama.cpp $LLAMA_VERSION (Vulkan, ~35 MB)"
  curl -fL --retry 5 --retry-delay 3 -o "$ROOT/releases/$TARBALL" \
    "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/${TARBALL}"
  mkdir -p "$DEST"
  tar -xzf "$ROOT/releases/$TARBALL" -C "$DEST" --strip-components=1
  ok "extraido em $DEST"
fi
ln -sfn "$DEST" "$ROOT/current"
ok "atalho: $ROOT/current -> $DEST"

# --------------------------------------------------------------- modelos
baixar() { # url destino bytes
  local url="$1" dest="$2" esperado="$3" atual
  atual=$(stat -c%s "$dest" 2>/dev/null || echo 0)
  if [ "$atual" = "$esperado" ]; then ok "$(basename "$dest") (completo)"; return; fi
  log "baixando $(basename "$dest") ($(awk -v b="$esperado" 'BEGIN{printf "%.1f GB", b/1e9}'))"
  curl -fL -C - --retry 30 --retry-delay 3 --retry-all-errors -o "$dest" "$url" \
    || die "falha ao baixar $url"
  atual=$(stat -c%s "$dest")
  [ "$atual" = "$esperado" ] || die "tamanho errado em $(basename "$dest"): $atual != $esperado"
  ok "$(basename "$dest") completo"
}

if [ "$BAIXAR_MODELOS" = 1 ]; then
  log "modelos GGUF (podem ser retomados se voce interromper)"
  baixar "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-MXFP4.gguf" \
         "$MODELS/gpt-oss-20b-mxfp4.gguf" 12109566624
  baixar "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
         "$MODELS/qwen3-4b-instruct-2507-q4_k_m.gguf" 2497281120
  baixar "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf" \
         "$MODELS/qwen3-8b-q4_k_m.gguf" 5027783488
else
  warn "modelos ignorados (--sem-modelos)"
fi

# ---------------------------------------------------------------- script
ln -sfn "$HERE/scripts/llama-local" "$BIN/llama-local"
chmod +x "$HERE/scripts/llama-local"
ok "comando: $BIN/llama-local"

# -------------------------------------------------------------- systemd
mkdir -p "$HOME/.config/systemd/user"
for u in llama-main llama-small llama-coder; do
  ln -sfn "$HERE/systemd/$u.service" "$HOME/.config/systemd/user/$u.service"
done
systemctl --user daemon-reload 2>/dev/null || warn "systemd --user indisponivel"

if [ "$HABILITAR_SERVICOS" = 1 ]; then
  systemctl --user enable --now llama-main.service llama-small.service 2>/dev/null \
    && ok "servicos habilitados (sobem no login): main + small" \
    || warn "nao consegui habilitar os servicos; rode 'llama-local restart' manualmente"
else
  warn "servicos nao habilitados (--sem-servicos). Use: llama-local main"
fi

# --------------------------------------------------------------- opencode
[ ! -f /.flatpak-info ] || die "rode este script no host, NAO dentro do Flatpak do OpenCode"
if flatpak info ai.opencode.opencode >/dev/null 2>&1; then
  CFG_DIR="$HOME/.var/app/ai.opencode.opencode/config/opencode"
  warn "OpenCode Flatpak detectado: a config vive em $CFG_DIR"
else
  CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
fi
mkdir -p "$CFG_DIR"
if [ -f "$CFG_DIR/opencode.jsonc" ] && ! grep -q '"local-coder"' "$CFG_DIR/opencode.jsonc"; then
  cp "$CFG_DIR/opencode.jsonc" "$CFG_DIR/opencode.jsonc.bak.$(date +%Y%m%d-%H%M%S)"
  warn "config existente salva em backup; sobrescrevendo"
fi
cp "$HERE/opencode/opencode.jsonc" "$CFG_DIR/opencode.jsonc"
ok "config do OpenCode: $CFG_DIR/opencode.jsonc"

# ---------------------------------------------------------------- atalho
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/ia-local.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=IA local (status)
Comment=Estado dos modelos locais usados pelo OpenCode
Exec=/bin/bash -c "$BIN/llama-local status; echo; read -p 'Enter para fechar'"
Icon=utilities-terminal
Terminal=true
Categories=Development;Utility;
EOF
ok "atalho no menu de aplicativos"

echo
log "pronto!"
echo "   llama-local status    # estado + VRAM"
echo "   llama-local coder     # Qwen2.5 Coder 7B na 8082 (para main/small)"
echo "   llama-local restart   # volta ao padrao (main + small)"
echo "   No OpenCode: /models -> 'gpt-oss-20b (local)'"
