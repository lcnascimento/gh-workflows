# gh-workflows
Reusable GitHub Actions workflows of the Homelab CI platform

## Preset do Renovate

O `default.json` é o preset que todo Consumidor estende no `renovate.json`:

```json
{
  "extends": ["github>lcnascimento/gh-workflows"]
}
```

Ele traz:

- schedule semanal (`before 8am on monday`, `America/Sao_Paulo`), `registryAliases` do Harbor e grupos de imagens Docker e de providers Terraform;
- as atualizações do `gh-workflows` num grupo só, com automerge de minor e patch quando a CI fica verde, e major com merge manual;
- customManagers para versões anotadas com `# renovate:` em `Dockerfile`, `.github/workflows/`, `action.yml` e `Makefile` (ou `*.mk`).

A anotação fica na linha anterior à versão, sem o prefixo `v`:

```make
# renovate: datasource=github-releases depName=golangci/golangci-lint
GOLANGCI_LINT_VERSION := 2.1.0
```
