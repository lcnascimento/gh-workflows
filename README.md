# gh-workflows
Reusable GitHub Actions workflows of the Homelab CI platform

Workflows reusáveis e composite actions da CI dos Consumidores. Um repo em Go, TypeScript, Python ou HCL que implementa o Contrato do Makefile ganha lint, testes e o gate do SonarQube chamando um único workflow.

| Componente | Referência | O que faz |
|---|---|---|
| `ci.yml` | `lcnascimento/gh-workflows/.github/workflows/ci.yml` | CI completa: `discover`, `lint`, um job por nível de teste e o `sonarqube` aninhado. |
| `sonarqube.yml` | `lcnascimento/gh-workflows/.github/workflows/sonarqube.yml` | Uma análise do SonarQube, invocável sozinha. |
| `relay.yml` | `lcnascimento/gh-workflows/.github/workflows/relay.yml` | Acorda o bot do Cyrus quando a CI de um PR dele falha ou o check "SonarQube Code Analysis" reprova, com limite de iterações por PR. |
| `lint-workflows` | `lcnascimento/gh-workflows/actions/lint-workflows` | actionlint e zizmor sobre os workflows do repo. |
| `ci-failure-comment` | `lcnascimento/gh-workflows/actions/ci-failure-comment` | Menciona um bot no PR cuja CI falhou ou cujo check do Sonar reprovou, uma vez por commit e até um limite por PR. É a lógica do `relay.yml`. |
| `default.json` | `github>lcnascimento/gh-workflows` | Preset do Renovate. |

Os exemplos de caller ficam em [`examples/.github/workflows/`](examples/.github/workflows/): copie para o `.github/workflows/` do Consumidor.

## Referência por SHA

Referencie todo componente pelo SHA do commit da release, com a tag num comentário:

```yaml
uses: lcnascimento/gh-workflows/.github/workflows/ci.yml@<sha> # v1.1.0
```

As releases são imutáveis: a tag de uma versão publicada nunca muda de commit. O comentário `# vX.Y.Z` é o que o Renovate lê para propor a próxima versão e trocar o SHA. As actions que o `ci.yml` e o `sonarqube.yml` usam por dentro (`setup-runtime`, `sonar-args`, `lint-workflows`) vêm do mesmo SHA do workflow chamado.

## Contrato do Makefile

O `ci.yml` não conhece a linguagem do Consumidor. Ele instala o runtime pelo manifesto e chama targets do Makefile ([ADR 0013 do `homelab`](https://github.com/lcnascimento/homelab/blob/main/docs/adr/0013-makefile-ci-contract.md)).

| Target | Obrigatório | O que a CI faz |
|---|---|---|
| `setup` | sim | Roda antes de todo outro target, em cada job. Instala as ferramentas do repo em `.bin/`, com versão fixa no Makefile e comentário `# renovate:`. É idempotente e pode ser vazio. |
| `lint` | sim | Roda no job `lint`, junto com actionlint e zizmor quando o repo tem `.github/workflows/`. |
| `format` | sim | Roda no job `lint`, seguido de `git diff --exit-code`. Código não formatado reprova o job. Não existe `format.check`. |
| `test.unit` | sim | Job `test-unit`. |
| `test.component`, `test.integration`, `test.e2e` | não | Um job cada, em paralelo com `test-unit`. O job `discover` detecta os presentes com `make -n`. |

- O Makefile põe `.bin/` no `PATH` com `export PATH := $(CURDIR)/.bin:$(PATH)`, e `.bin/` fica no `.gitignore`.
- Os targets `test.*` escrevem a cobertura em `.coverage/`, um arquivo por nível, com a extensão do formato: `.out` (coverprofile do Go), `.lcov` (JS/TS) e `.xml` (Cobertura do Python). Ex.: `.coverage/unit.out`. O Sonar recebe cada arquivo pela extensão, sem configuração no Consumidor.
- O runtime vem do manifesto, sem versão no workflow:

  | Manifesto | Action |
  |---|---|
  | `go.mod` | `actions/setup-go` com `go-version-file` |
  | `.nvmrc` | `actions/setup-node` com `node-version-file` |
  | `.python-version` ou `pyproject.toml` | `astral-sh/setup-uv`; os targets chamam o Python por `uv run` |
  | `.opentofu-version` | `opentofu/setup-opentofu` com `tofu_version_file`, sem wrapper |

- Um teste que precisa de banco ou de outro serviço sobe o serviço pelo próprio target. O `ci.yml` não declara `services:`.
- O Contrato não traz mise nem versões default de ferramentas: cada Consumidor fixa as suas no Makefile.

## `ci.yml`

### Inputs

| Input | Tipo | Default | Descrição |
|---|---|---|---|
| `runner` | string | `''` | Label do runner. Vazio cai em `vars.CI_RUNNER` e depois em `ubuntu-latest`. |
| `working-directory` | string | `.` | Diretório do Makefile e dos manifestos, relativo à raiz do repo. |
| `sonar` | boolean | `true` | Roda a análise do SonarQube depois dos testes. |
| `project-key` | string | `''` | Chave do projeto Sonar. Vazio usa o nome do repo. |

### Secrets

Os secrets têm nome de propósito. Passe cada um explicitamente; nunca use `secrets: inherit`.

| Secret | Obrigatório | Descrição |
|---|---|---|
| `sonar-token` | só com `sonar: true` | Token de análise do projeto Sonar. Sem ele o job `sonarqube` falha no step `sonar-token`; um repo sem Sonar chama com `sonar: false`. |
| `doppler-token` | não | Service token do Doppler. Com ele, só `test.integration` e `test.e2e` rodam sob `doppler run`, e o token só existe no step do `make`. Sem ele, os targets rodam com `make` direto. |

### Outputs

| Output | Descrição |
|---|---|
| `runner` | Label do runner em que os jobs rodaram. |
| `coverage-artifact` | Prefixo dos artifacts de cobertura, um por nível, com nome `<prefix>-<nível>`. Baixe com `actions/download-artifact` e `pattern: <prefix>-*`. |

### Variáveis

Lidas do repo ou da organização do caller:

| Variável | Uso |
|---|---|
| `CI_RUNNER` | Runner default do repo (ex.: o scale set do `homelab-prod`). |
| `SONAR_HOST_URL` | URL do servidor que o scanner usa. Obrigatória com `sonar: true`. |
| `SONAR_PUBLIC_URL` | Opcional. URL pública do SonarQube para o link no summary do job. |

### Jobs

| Job | Roda quando | Permissões |
|---|---|---|
| `discover` | sempre, no `ubuntu-latest` | `contents: read` |
| `lint` | depois do `discover` | `contents: read` |
| `test-unit` | depois do `discover` | `contents: read` |
| `test-component`, `test-integration`, `test-e2e` | o target existe | `contents: read` |
| `sonarqube` | `sonar: true`, nenhum teste falhou e a run não foi cancelada | `contents: read` |

## `sonarqube.yml`

Uma análise só, num job com `fetch-depth: 0` e o `SonarSource/sonarqube-scan-action`.

- No `pull_request`, passa `sonar.scm.revision` igual ao head sha do PR e não espera o Quality Gate: o veredito chega pelo check run da App do SonarQube.
- Na branch default, espera o Quality Gate com `sonar.qualitygate.wait=true` e reprova o job se ele falhar.
- O caller não precisa de job no `closed` do PR, e o reusável não define `concurrency`.
- Um `sonar-project.properties` no `working-directory` é opcional e serve só para `sonar.sources`, `sonar.tests` e `sonar.exclusions`. A chave do projeto e a cobertura vêm do workflow.

| Input | Tipo | Default | Descrição |
|---|---|---|---|
| `runner` | string | `''` | Label do runner, com o mesmo fallback do `ci.yml`. |
| `working-directory` | string | `.` | Diretório base do projeto, relativo à raiz do repo. |
| `project-key` | string | `''` | Chave do projeto Sonar. Vazio usa o nome do repo. |
| `coverage-artifact` | string | `''` | Prefixo dos artifacts de cobertura da run (o output `coverage-artifact` do `ci.yml`). Vazio analisa sem cobertura. |

Secret `sonar-token` (token de análise do projeto) e variáveis `SONAR_HOST_URL` e `SONAR_PUBLIC_URL`, como no `ci.yml`. Sem o token ou sem `SONAR_HOST_URL`, o job falha no step `sonar-token`.

## `relay.yml`

O relay acorda o Cyrus quando a CI do Consumidor falha, quando o check run "SonarQube Code Analysis" reprova ou quando o Revisor deixa threads abertas num PR aberto pelo bot. O caller reage ao `workflow_run` (`completed`) do workflow de CI, ao `check_run` (`completed`) e ao `pull_request_review` (`submitted`), e chama o reusável, que roda a action `ci-failure-comment` do mesmo SHA.

| Input | Tipo | Default | Descrição |
|---|---|---|---|
| `runner` | string | `''` | Label do runner, com o mesmo fallback do `ci.yml`. |
| `bot-login` | string | obrigatório | Login do bot, ex.: `homelab-cyrus[bot]`. O relay só age em PRs com esse autor e menciona esse login. |
| `reviewer-login` | string | `''` | Login do Revisor, ex.: `greptile-apps[bot]`. Uma review enviada por esse login acorda o bot nas threads abertas. Vazio ignora as reviews. |
| `max-iterations` | number | `3` | Máximo de relatos automáticos por PR. |

Sem secrets: o relay usa o `GITHUB_TOKEN` do caller.

A cada `workflow_run`, `check_run` ou `pull_request_review`, o relay:

1. ignora um check run com outro nome que não "SonarQube Code Analysis";
2. ignora a run ou o check se a conclusão não for `failure`;
3. acha o PR (pelo evento ou, se a lista do evento vier vazia, pelo head SHA entre os PRs abertos) e o ignora se estiver fechado ou se o autor não for `bot-login`;
4. numa review, conta as threads não resolvidas abertas por `reviewer-login` cuja última resposta não é do bot, e ignora a review se não houver nenhuma;
5. ignora o SHA que já tem relato, venha ele da CI, do Sonar ou de uma review;
6. ao atingir `max-iterations` relatos, posta um aviso final sem menção, uma vez só, e depois não comenta mais;
7. senão, comenta mencionando o bot, com o link da run e os jobs que falharam, com o link do check do Sonar ou com o link da review e o número de threads abertas.

A falha da CI, a reprovação do Sonar e a review dividem o marcador, o contador e o aviso final: no mesmo SHA, o bot recebe um comentário só, e ele conta uma iteração. A review marca o head SHA atual do PR, não o commit revisado. A contagem sai dos comentários do PR, sem estado externo. Cada relato leva o marcador invisível `<!-- cyrus-ci-failure sha=<sha> -->` na última linha, e o aviso final leva `<!-- cyrus-ci-failure limit -->`. Só conta o marcador que fecha um comentário de um autor do tipo `Bot` diferente de `bot-login`, como o `github-actions[bot]` do `GITHUB_TOKEN`. Um humano ou o próprio Cyrus que cite um relato não muda a contagem.

O reusável não faz checkout: o script vem da action no SHA do reusável, e nenhum código do PR roda no gatilho privilegiado. Por isso o `workflow_run` e o `check_run` do caller levam um `# zizmor: ignore[dangerous-triggers]`.

O `if` do job pré-filtra os eventos para não gastar runner: só entra num `workflow_run` que falhou, num `check_run` do Sonar que reprovou ou num `pull_request_review` enviado por `reviewer-login` (a comparação de logins ignora maiúsculas, e um `reviewer-login` vazio barra toda review). Outros eventos, como um `workflow_dispatch`, passam e a action os ignora. O job define a própria `concurrency` por head SHA (o `pull_request.head.sha` numa review), e cai no `run_id` quando o evento não tem head SHA. Assim os eventos da CI, do Sonar e das reviews do mesmo commit rodam em série, sem comentário duplicado, e as runs verdes e os check runs de outros nomes não ocupam a fila nem substituem um relato pendente. O caller não precisa de `concurrency`.

| Job | Permissões |
|---|---|
| `relay` | `actions: read`, `pull-requests: write` |

`pull-requests: write` lê o PR e comenta nele. `actions: read` lista os jobs da run para o comentário: num repo privado, a API de jobs nega o token sem ela.

## `actions/lint-workflows`

Roda actionlint e zizmor sobre os arquivos `*.yml` e `*.yaml` de um diretório. Sem workflows no diretório, só emite um aviso.

| Input | Default | Descrição |
|---|---|---|
| `path` | `.github/workflows` | Diretório dos workflows. |

O zizmor usa o `.github/zizmor.yml` ou o `zizmor.yml` do repo quando existe. Sem eles, usa a configuração da action, que desliga a regra `self-repository` porque o actionlint ainda não aceita a sintaxe `$/`. O job que chama a action precisa de `contents: read`.

## `actions/ci-failure-comment`

Num workflow disparado por `workflow_run`, por `check_run` do "SonarQube Code Analysis" ou por `pull_request_review`, comenta no PR aberto da run ou do check que falhou, ou da review que deixou threads abertas do `reviewer` sem resposta do bot, mencionando um bot (ex.: o Cyrus), uma vez por commit e no máximo `max-attempts` vezes por PR. Ao atingir o limite, posta um aviso final sem menção. As regras do relay moram nela: o `if` do job do `relay.yml` repete o filtro de evento e de conclusão só para não subir um runner à toa, e a action decide sozinha quando a chamam direto.

| Input | Default | Descrição |
|---|---|---|
| `bot` | obrigatório | Login do bot, ex.: `homelab-cyrus[bot]`. |
| `author` | `""` | Só comenta em PRs desse autor. Vazio aceita qualquer autor. |
| `reviewer` | `""` | Login do Revisor, ex.: `greptile-apps[bot]`, cujas threads abertas acordam o bot num `pull_request_review`. Vazio ignora as reviews. |
| `max-attempts` | `"3"` | Máximo de relatos de falha por PR. |
| `event-path` | `${{ github.event_path }}` | Caminho do payload do `workflow_run`, do `check_run` ou do `pull_request_review`. |
| `token` | `${{ github.token }}` | Token para ler PRs e comentar. Precisa comentar como um autor do tipo `Bot` (o `GITHUB_TOKEN` ou o token de um GitHub App), senão a action não reconhece os próprios relatos. |

O job que chama a action precisa de `pull-requests: write`. Com `actions: read`, o comentário lista os jobs que falharam; sem ela, a action emite um aviso e comenta sem a lista.

## Teto de permissões

O caller começa com `permissions: {}` no workflow e concede, no job que chama o componente, só o teto abaixo. Cada job do reusável pede o mínimo dele, que nunca passa do teto do caller.

| Componente | Permissões no job do caller |
|---|---|
| `ci.yml` | `contents: read` |
| `sonarqube.yml` | `contents: read` |
| `lint-workflows` | `contents: read` |
| `relay.yml` | `actions: read`, `pull-requests: write` |
| `ci-failure-comment` | `pull-requests: write` (mais `actions: read` para listar os jobs) |

## Runner

Todo reusável roda em `inputs.runner || vars.CI_RUNNER || 'ubuntu-latest'`. A exceção é o `discover` do `ci.yml`, que roda sempre no `ubuntu-latest`: ele só faz checkout e `make -n`, e num runner sob demanda atrasaria o início dos jobs seguintes. O repo escolhe o runner pela variável `CI_RUNNER`. Os exemplos têm um `workflow_dispatch` com input `runner` (default `ubuntu-latest`) para rodar a CI fora do cluster quando o runner do `homelab-prod` está fora do ar. No `pull_request` e no `push`, `inputs.runner` é vazio e vale o fallback.

## Exemplos de caller

Os reusáveis não definem `concurrency`, exceto o `relay.yml`, que serializa os relatos do mesmo SHA: o caller decide o cancelamento. Os exemplos cancelam a run anterior do mesmo PR e nunca cancelam uma run da `main`.

- [`ci.yml`](examples/.github/workflows/ci.yml): chama o `ci.yml` com `sonar-token` e `doppler-token`.
- [`sonarqube.yml`](examples/.github/workflows/sonarqube.yml): chama o `sonarqube.yml` sozinho, para um repo cuja CI não é o `ci.yml`.
- [`relay.yml`](examples/.github/workflows/relay.yml): chama o `relay.yml` quando o workflow `ci` termina, quando um check run termina e quando uma review é enviada, com `reviewer-login: greptile-apps[bot]`. O `workflow_run` e o `check_run` levam um `# zizmor: ignore[dangerous-triggers]` porque o relay só lê os metadados da run, do check e do PR e nunca faz checkout.
- [`ci-failure.yml`](examples/.github/workflows/ci-failure.yml): menciona o Cyrus quando o workflow `ci` falha num PR. O `workflow_run` leva um `# zizmor: ignore[dangerous-triggers]` porque o job só lê os metadados da run e nunca faz checkout do código do PR.

Os exemplos `ci.yml` e `sonarqube.yml` são alternativas: copie um ou outro, nunca os dois. O `ci.yml` já roda o `sonarqube.yml` aninhado, e os dois juntos fazem duas análises por evento.

A `self-ci` passa os exemplos pelo actionlint e pelo zizmor no job `lint-examples`. O Renovate deste repo atualiza o SHA dos exemplos a cada release, como num Consumidor, então eles sempre apontam para a última versão.

## Versionamento

O release-please gera uma versão única para o repo inteiro a partir dos Conventional Commits da `main`. `fix:` sobe o patch, `feat:` sobe o minor, e `feat!:` ou um rodapé `BREAKING CHANGE:` sobe o major.

Uma mudança exige major quando:

- um input ou secret obrigatório de um reusável muda ou sai;
- um target obrigatório do Contrato do Makefile (`setup`, `lint`, `format`, `test.unit`) muda.

O preset do Renovate faz automerge de minor e patch do `gh-workflows` e deixa o major para merge manual, para que o dono do Consumidor revise a quebra de contrato.

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

O Consumidor estende o preset com as próprias regras no `renovate.json`; uma regra do repo vale por cima da do preset:

```json
{
  "extends": ["github>lcnascimento/gh-workflows"],
  "packageRules": [
    {
      "matchDatasources": ["go"],
      "groupName": "go modules"
    }
  ]
}
```
