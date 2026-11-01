# ia-local-opencode

Modelos de linguagem rodando **na sua máquina**, integrados ao [OpenCode](https://opencode.ai)
como providers OpenAI-compatible: **sem API key, sem cota, sem limite de uso** — e o seu
código não sai do computador.

Testado em: Xeon E5-2667 v4 (16 threads), 32 GB RAM, **Radeon RX 580 2048SP 8 GB**
(Polaris / gfx803), Zorin OS 17 (base Ubuntu 24.04), OpenCode 2.1.3 Flatpak.

```
┌───────────────────────────────┐        ┌──────────────────────────────┐
│ OpenCode (Flatpak)            │        │ host (fora do sandbox)       │
│  provider local        ───────┼──8080──▶ llama-server  gpt-oss-20b  │
│  provider local-small  ───────┼──8081──▶ llama-server  Qwen3 4B     │
│  provider local-coder  ───────┼──8082──▶ llama-server  Qwen3 8B    │
└───────────────────────────────┘        └──────────────┬───────────────┘
                                                        │ Vulkan (RADV)
                                                        ▼
                                                 Radeon RX 580 8 GB
```

## Por que assim (e não Ollama)

| Problema | Solução aqui |
|---|---|
| Ollama/ROCm não suporta **gfx803** (Polaris) — upstream marcou "not planned" | build **Vulkan** oficial do `llama.cpp`, usa o RADV do Mesa que já existe |
| Rodar inferência **dentro do Flatpak** do OpenCode derrubava o app | os servidores rodam **no host**; o OpenCode só fala `127.0.0.1` |
| 12 GB de modelo em 8 GB de VRAM | MoE com `--n-cpu-moe`: experts na RAM, atenção na GPU |
| Config do Flatpak ignorada | a config real fica em `~/.var/app/ai.opencode.opencode/config/opencode/` |

## Modelos

| Modelo | Papel | Porta | Contexto | Tamanho |
|---|---|---|---|---|
| **gpt-oss-20b** (MXFP4, MoE 21B/3,6B ativos) | agente principal: raciocínio, plano, ferramentas | 8080 | 32k | 12,1 GB |
| **Qwen3-4B-Instruct-2507** (Q4_K_M) | subagentes rápidos: varrer arquivos, resumir | 8081 | 8k | 2,5 GB |
| **Qwen3-8B** (Q4_K_M, modo "coder") | código: gerar/editar/revisar, com ferramentas | 8082 | 16k | 5,0 GB |

> **Por que Qwen3-8B e não Qwen2.5-Coder-7B?** Testei os dois: o Qwen2.5-Coder-7B é
> ótimo em código, mas responde chamadas de ferramenta como texto
> (` ```json {"name": ...} ``` `) em vez de `<tool_call>`, e o llama.cpp não consegue
> convertê-las em `tool_calls` — ou seja, o agente não edita arquivos. O Qwen3-8B
> emite as chamadas no formato certo e também é forte em código. Se você só quer
> gerar código no chat (sem ferramentas), o Qwen2.5-Coder-7B serve:
> `CODER_MODEL=~/Modelos/qwen2.5-coder-7b-instruct-q4_k_m.gguf llama-local coder`.

Os dois primeiros rodam **ao mesmo tempo** (7,5 de 8 GB de VRAM).
O coder é denso e usa ~6,5 GiB (com o desktop), então roda **sozinho**:
`llama-local coder` libera a VRAM antes, e `llama-local restart` volta ao padrão.
Os units têm `Conflicts=`, então `systemctl --user start llama-coder` já derruba os outros.

## Desempenho medido (RX 580, Vulkan)

| Modelo | Prompt (pp) | Geração (tg) |
|---|---|---|
| gpt-oss-20b | ~138 tok/s | ~18 tok/s |
| Qwen3 4B | ~243 tok/s | ~33 tok/s |
| Qwen3 8B (coder) | ~141 tok/s | ~25 tok/s |

> Números de `pp` em prompt real de ~1.600 tokens. Prompt curto parece muito mais
> lento (30–50 tok/s) porque o tempo é dominado pela inicialização do grafo.
> Com os dois servidores no ar a VRAM fica em **~7,5 GiB de 8 GiB**;
> o coder sozinho fica em ~6,5 GiB.

## Requisitos

- GPU com **Vulkan** (`mesa-vulkan-drivers` em AMD/Intel; driver proprietário em NVIDIA)
- **8 GB de VRAM** para o conjunto padrão (menos VRAM? aumente `--n-cpu-moe`)
- 32 GB de RAM (o gpt-oss deixa ~10 GB de experts na CPU)
- ~20 GB de disco para os três modelos
- `curl`, `tar`, `systemd --user`

## Instalação

```bash
git clone https://github.com/ricb86/ia-local-opencode.git
cd ia-local-opencode
./install.sh
```

O script:

1. confere o Vulkan e mostra qual GPU foi detectada;
2. baixa o `llama.cpp` (release Vulkan oficial, ~35 MB) para `~/.local/share/llama.cpp`;
3. baixa os 3 modelos GGUF para `~/Modelos` (retomável com `-C -`);
4. instala `llama-local` em `~/.local/bin` e os serviços em `~/.config/systemd/user`;
5. habilita `llama-main` + `llama-small` para subirem no login;
6. grava a config do OpenCode no lugar certo (detecta Flatpak).

Opções: `--sem-modelos` (não baixa os 12 GB), `--sem-servicos`.

## Usar no OpenCode

Depois de instalar, no OpenCode: **`/models`** → escolha
`gpt-oss-20b (local)`. Nada de `/connect`.

| Agente | Modelo padrão |
|---|---|
| `build`, `plan` | gpt-oss-20b |
| `explore`, `general` | Qwen3 4B |
| `coder` | Qwen3 8B (coder) |

A config que o instalador grava:

```jsonc
// ~/.var/app/ai.opencode.opencode/config/opencode/opencode.jsonc   (Flatpak)
// ~/.config/opencode/opencode.jsonc                                (instalação normal)
{
  "model": "local/gpt-oss-20b",
  "providers": {
    "local": {
      "name": "Local (llama.cpp Vulkan)",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "http://127.0.0.1:8080/v1" },
      "models": {
        "gpt-oss-20b": { "name": "gpt-oss-20b (local)", "limit": { "context": 32768, "output": 8192 } }
      }
    }
  },
  "agents": { "build": { "model": "local/gpt-oss-20b" } }
}
```

Para recarregar sem reiniciar o app (com o OpenCode instalado como Flatpak):

```bash
/app/main/resources/opencode-cli reload
/app/main/resources/opencode-cli models     # confere se os providers apareceram
```

## Comandos

```bash
llama-local status    # o que está no ar + VRAM
llama-local main      # gpt-oss-20b (8080)
llama-local small     # Qwen3 4B   (8081)
llama-local coder     # Qwen3 8B coder (8082) — para main+small antes
llama-local restart   # volta ao padrão: serviços main + small
llama-local stop      # para tudo
llama-local teste     # benchmark com llama-bench
```

Serviços (sobem no login):

```bash
systemctl --user status llama-main llama-small
systemctl --user restart llama-main
journalctl --user -u llama-main -f
```

Trocar o coder pelo principal (e vice-versa) é automático: os units têm
`Conflicts=`, então `systemctl --user start llama-coder` já derruba os outros.

## Ajuste fino

### Quanto do MoE fica na GPU — `--n-cpu-moe`

Medido neste hardware, gpt-oss-20b sozinho:

| `--n-cpu-moe` | VRAM | Geração | Observação |
|---|---|---|---|
| 24 | 2,3 GB | ~16 tok/s | sobra VRAM, mas desperdiça GPU |
| 18 | 5,0 GB | ~18 tok/s | **padrão**: cabe junto do 4B |
| 12 | 7,0 GB | ~23 tok/s | mais rápido, mas não cabe com outro modelo |

### KV cache quantizado

`-ctk q8_0 -ctv q8_0` corta quase metade da VRAM do contexto sem perda perceptível.
Sem isso, 32k no gpt-oss consome ~1,6 GB só de cache.

### Raciocínio do Qwen3 (`enable_thinking`)

O Qwen3-8B pensa antes de responder (gasta tokens). Dá para desligar com
`chat_template_kwargs`, **mas neste build do llama.cpp isso quebra o tool calling**
(o modelo passa a devolver a chamada como JSON em markdown e o servidor não a
interpreta). Por isso o coder roda com raciocínio ligado. Se você usar o modelo
só como chat, pode desligar no request:

```bash
curl -s http://127.0.0.1:8082/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "qwen3-8b",
  "messages": [{"role": "user", "content": "17*23?"}],
  "chat_template_kwargs": { "enable_thinking": false }
}'
```

### Esforço de raciocínio (gpt-oss)

O gpt-oss "pensa" antes de responder e isso custa tokens a 18 tok/s. Ajuste por request:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gpt-oss-20b",
  "messages": [{"role": "user", "content": "17*23?"}],
  "chat_template_kwargs": { "reasoning_effort": "low" }
}'
```

Medido com a mesma pergunta: `low` 20 tokens / 4,0 s · `medium` 61 / 5,9 s · `high` 71 / 6,5 s.

## Solução de problemas

| Sintoma | Causa / solução |
|---|---|
| modelos não aparecem no `/models` | config no lugar errado: no Flatpak é `~/.var/app/ai.opencode.opencode/config/opencode/opencode.jsonc` |
| `connection refused` | servidor parado: `llama-local status` / `llama-local restart` |
| app fecha ao carregar modelo | está rodando `llama-server` **dentro** do sandbox; rode no host |
| `failed to allocate Vulkan buffer` | VRAM cheia: `llama-local stop` ou aumente `--n-cpu-moe` |
| lento demais | use `local-small` para tarefas simples; `reasoning_effort: low` no gpt-oss |
| "no usable GPU" | falta `mesa-vulkan-drivers`; teste com `vulkaninfo --summary` |
| segunda GPU/VRAM | `-ngl 99` manda tudo; reduza se necessário |

Logs: `~/.local/share/llama.cpp/logs/` (`server-*.log`, `service-*.log`).

## Estrutura

```
.
├── install.sh                  # instalador (Vulkan + modelos + systemd + config)
├── scripts/llama-local         # controle dos modelos
├── systemd/llama-*.service     # serviços de usuário
├── opencode/opencode.jsonc     # config-exemplo com os 3 providers
└── LICENSE
```

## Créditos

- [llama.cpp](https://github.com/ggml-org/llama.cpp) — inferência
- [gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b) (OpenAI, Apache-2.0)
- [Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) (Alibaba, Apache-2.0)
- [Qwen3-8B](https://huggingface.co/Qwen/Qwen3-8B) (Alibaba, Apache-2.0)

MIT — veja [LICENSE](LICENSE).
