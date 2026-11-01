# IA local (llama.cpp + Vulkan) para o OpenCode

A documentação completa agora está no README do projeto:

- **`~/IA-local/README.md`** (ou no GitHub: https://github.com/ricb86/ia-local-opencode)

Resumo rápido:

| Modelo | Porta | Uso |
|---|---|---|
| gpt-oss-20b | 8080 | agente principal (`build`/`plan`) |
| Qwen3 4B | 8081 | subagentes (`explore`/`general`) |
| Qwen3 8B (coder) | 8082 | código — roda sozinho |

```bash
llama-local status     # estado + VRAM
llama-local coder      # troca para o coder (libera a VRAM antes)
llama-local restart    # volta ao padrão (main + small)
llama-local stop       # para tudo
```

Serviços sobem no login: `systemctl --user status llama-main llama-small`.

Config do OpenCode (Flatpak): `~/.var/app/ai.opencode.opencode/config/opencode/opencode.jsonc`.
