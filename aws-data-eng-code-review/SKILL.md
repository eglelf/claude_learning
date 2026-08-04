---
name: aws-data-eng-code-review
description: Executa code review técnico de projetos de Engenharia de Dados em AWS (Glue/PySpark, Lambda, Step Functions, Athena, Glue Catalog, S3, DynamoDB, RDS, SageMaker Processing, Maestro/orquestração, scripts Python e Terraform) comparando duas branches de um repositório GitHub e gerando o arquivo /workspaces/resultado_codereview.md. Use sempre que o usuário pedir code review, revisão de código, análise de PR/MR, "revisar a branch X contra a main", avaliação de merge/deploy, validação de cobertura de testes ou parecer de aprovação para produção — mesmo que não use a palavra "skill" e mesmo que informe apenas o link do repositório e o nome da branch. Também use quando pedirem para verificar se um projeto está apto a subir para produção.
---

# Code Review — Engenharia de Dados AWS

Review objetivo, orientado a **impedimentos de deploy**. O objetivo não é opinar sobre estilo, é responder: *isso pode ir para produção? se não, por quê e o que exatamente precisa mudar?*

O revisor humano (Tech Lead) usa este relatório como insumo de decisão. Achado sem evidência rastreável (arquivo + linha + trecho) é ruído e custa mais caro que a ausência do achado, porque obriga o Tech Lead a reconferir tudo.

## Entradas necessárias

| Entrada | Obrigatória | Default |
|---|---|---|
| URL do repositório GitHub (ou path local já clonado) | sim | — |
| Branch com as modificações | sim | — |
| Branch de comparação | não | `main` |
| Workspace | não | `/workspaces` |

Se faltar repositório ou branch de modificações, pergunte apenas isso e siga. Não pergunte nada que dê para inferir do repositório.

## Princípios

- **Escopo é o diff.** Só entra no relatório o que foi alterado nesta branch ou o que quebra por causa da alteração. Código legado feio que ninguém tocou não é achado.
- **Severidade orientada a produção.** Classifique pelo impacto real em execução: perda/duplicação de dados, custo, falha silenciosa, segurança, indisponibilidade. Preferência estética não é achado.
- **Evidência obrigatória.** Todo achado cita `caminho/arquivo.py:linha` e o trecho relevante. Sem isso, não reporte.
- **Incerteza é explícita.** Se não conseguiu executar um gate (sem rede, sem dependência, sem credencial), registre "Não verificado — motivo". Nunca simule resultado de teste, cobertura ou `terraform plan`.
- **Falso positivo é caro.** Antes de marcar bloqueador, procure a mitigação no próprio repositório (retry na orquestração, `WHERE` aplicado a montante, config no Terraform, tratamento no chamador). Se a mitigação existe, rebaixe ou descarte.

## Fluxo

### Etapa 1 — Preparar o repositório

```bash
bash scripts/preparar_review.sh <repo_url> <branch_feature> [branch_base] [workspace]
```

O script clona (ou atualiza) em `<workspace>/<repo>`, faz `fetch`, calcula o `merge-base` e grava os artefatos em `<workspace>/.review/<repo>/`:

`info.env`, `commits.txt`, `arquivos_alterados.txt`, `diff_stat.txt`, `diff_completo.patch`, `dominios.txt`.

O diff é sempre contra o **merge-base** (`git diff merge-base..feature`), não contra o HEAD da base — isso isola o que a branch realmente introduziu e evita atribuir ao autor commits que vieram da `main`.

Se o script falhar (rede bloqueada, repositório privado sem credencial), reporte o erro exato ao usuário e pare. Não invente o conteúdo do repositório.

### Etapa 2 — Mapear escopo e domínios

Leia `arquivos_alterados.txt`, `diff_stat.txt` e `dominios.txt`. Confirme a classificação heurística do script lendo os arquivos — nome de pasta engana (`utils/glue_helper.py` pode ser só string formatting).

Carregue **apenas** os checklists dos domínios presentes no diff:

| Domínio detectado | Ler |
|---|---|
| PySpark, AWS Glue, EMR, Iceberg/Delta | `references/pyspark-glue.md` |
| Lambda, Step Functions, Maestro/Airflow, SageMaker Processing, EventBridge, SQS/Kinesis | `references/orquestracao-serverless.md` |
| Athena, Glue Catalog, S3, DynamoDB, RDS, SQL | `references/dados-armazenamento.md` |
| Terraform, CloudFormation, CDK, pipelines de deploy | `references/terraform-iac.md` |
| Qualquer código Python e testes | `references/python-qualidade-testes.md` |
| IAM, segredos, PII, logs, métricas, custo | `references/seguranca-observabilidade.md` |

`python-qualidade-testes.md` e `seguranca-observabilidade.md` valem para praticamente todo review — carregue por padrão quando houver código.

### Etapa 3 — Leitura dirigida

Diff isolado esconde contexto. Para cada arquivo alterado que contenha lógica:

1. Leia o arquivo **inteiro**, não só o hunk.
2. Leia quem chama a função alterada e o que consome a saída dela.
3. Correlacione código ↔ infraestrutura: recurso novo referenciado no código (bucket, tabela, fila, secret, role) precisa existir no Terraform do repositório ou ser declaradamente externo.
4. Verifique se mudança de contrato (schema, coluna, tipo, nome de parâmetro, formato de arquivo, chave de partição) tem consumidor no repositório ou documentado.

**Diff grande (> ~3.000 linhas):** priorize nesta ordem — IaC e IAM → escrita/DDL de dados → transformação PySpark/SQL → orquestração → utilitários → testes → docs. Registre no relatório o que ficou sem análise profunda.

### Etapa 4 — Gates automáticos

Execute na ordem e guarde a saída bruta como evidência.

**1. Testes e cobertura (≥ 90%)**

```bash
bash scripts/rodar_cobertura.sh [workspace] [repo_name]
```

Comando canônico do time (executado dentro do repositório):

```bash
pytest -q --cov=app --ignore=app/tests/test_integration.py app/tests
```

Se a estrutura for diferente (`src/` em vez de `app/`, testes fora de `app/tests`), adapte o comando, **registre no relatório o comando efetivamente usado** e sinalize a divergência de padrão como achado MÉDIO.

Cobertura só é confiável se os testes forem confiáveis: cheque no diff se `omit`/`exclude_lines`/`fail_under` em `.coveragerc`, `setup.cfg` ou `pyproject.toml` foram alterados para inflar o número, e se os testes novos têm asserções reais. Cobertura de 95% com testes sem `assert` é BLOQUEADOR mesmo passando no gate.

**2. README atualizado**

Compare o diff funcional com o `README.md`. O README precisa refletir: novos parâmetros/variáveis de ambiente, mudança de comando de execução, novas tabelas/fontes/destinos, nova dependência de infraestrutura, mudança de agendamento/orquestração, alteração de contrato de saída.

- README não alterado e a mudança afeta execução, parâmetros ou contrato → **BLOQUEADOR**.
- README não alterado e a mudança é interna (refactor sem efeito externo) → **BAIXO** ou não reportar.

**3. Segredos e dados sensíveis**

`grep -rEn` no diff por `AKIA[0-9A-Z]{16}`, `aws_secret_access_key`, `password|senha|passwd`, `token|api[_-]?key`, `BEGIN (RSA|OPENSSH|PRIVATE) KEY`, `jdbc:.*://.*:.*@`, `.env`, `.pem`, `.p12` versionados. **Nunca copie o valor do segredo para o relatório** — mascare (`AKIA****REDACTED`) e cite só arquivo e linha.

**4. IaC (quando houver Terraform)**

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
```

`tflint`/`checkov` se disponíveis. **Não rode `plan` sem credenciais explicitamente fornecidas pelo usuário e nunca rode `apply`/`destroy`.** Sem `plan`, a análise de recriação de recurso é estática: aponte como risco a confirmar, não como fato.

### Etapa 5 — Análise por domínio

Percorra os checklists carregados. Para cada item: verificado e OK, verificado e com achado, ou não aplicável. Itens não verificáveis viram "Não verificado" no relatório.

### Etapa 6 — Consolidar e classificar

| Severidade | Critério | Efeito no veredito |
|---|---|---|
| **BLOQUEADOR** | Impede deploy. Perda/duplicação/corrupção de dados, falha silenciosa, segredo exposto, IAM permissivo demais, quebra de contrato sem migração, recurso sem IaC, teste falhando, cobertura < 90%, recriação de recurso stateful, OOM/estouro de custo certo no volume real | REPROVADO |
| **ALTO** | Falha provável sob carga ou erro, com mitigação operacional possível: skew/shuffle sem tratamento, scan sem filtro de partição, small files, ausência de retry/DLQ, log sem correlação, caminho crítico sem teste | APROVADO COM RESSALVAS |
| **MÉDIO** | Dívida técnica relevante: hardcode que deveria ser parâmetro, duplicação, divergência de padrão do time, ausência de tipagem em interface pública | Não bloqueia |
| **BAIXO** | Melhoria pontual sem risco operacional | Não bloqueia |

Veredito: ≥1 BLOQUEADOR → **REPROVADO**. Zero bloqueadores e ≥1 ALTO → **APROVADO COM RESSALVAS**. Nenhum dos dois → **APROVADO**.

Antes de fechar: deduplique achados com a mesma causa raiz (um achado, lista de ocorrências), e reordene por severidade e depois por custo de correção.

### Etapa 7 — Gerar o relatório

Escreva **`<workspace>/resultado_codereview.md`** (default `/workspaces/resultado_codereview.md`) seguindo exatamente o esqueleto de `references/template-relatorio.md`. Português, técnico, sem preâmbulo.

### Etapa 8 — Verificação final

```bash
git -C <workspace>/<repo> status --porcelain   # deve estar vazio
```

Confirme: relatório existe e está preenchido, todo achado tem arquivo:linha, todo gate tem resultado ou justificativa de não execução, nenhum segredo em texto claro no relatório, repositório sem modificações.

Ao responder no chat, entregue no máximo: veredito, contagem por severidade, os bloqueadores em uma linha cada e o caminho do arquivo. O detalhe está no relatório.

## Restrições

**Nunca modifique o projeto.** Sem editar arquivo, sem corrigir bug, sem formatar, sem `black -w`, `isort`, `ruff --fix`, `terraform fmt` (só `-check`).

**Nunca escreva no Git ou no GitHub.** Sem `add`, `commit`, `push`, `merge`, `rebase`, `tag`, `branch`, sem abrir PR, sem comentar em PR. `checkout --detach` no commit da feature para rodar os testes é permitido e é o único write no working tree.

**Nunca execute o projeto contra ambiente real.** Só a suíte de testes. Nada de rodar job Glue, script com `boto3` apontando para conta real, migração de banco, `terraform apply`/`destroy`, deploy.

**Nunca instale dependências dentro do repositório.** venv fora da árvore do projeto (o script já faz isso), `PYTHONDONTWRITEBYTECODE=1`, `-p no:cacheprovider`, `COVERAGE_FILE` fora do repositório.

**Nunca reporte:** estilo/formatação (a menos que o próprio lint configurado do projeto falhe), refatoração ampla não solicitada, achado em arquivo intocado (exceto quando o diff o quebra), especulação sem evidência, número de linha inventado, valor de segredo, elogio inflado — a seção de pontos positivos tem no máximo 5 linhas.

**Nunca pare no primeiro gate reprovado.** Cobertura abaixo do mínimo não encerra o review; conclua todas as etapas para o autor corrigir tudo de uma vez.

## Armadilhas frequentes

- Marcar `collect()` como bloqueador sem olhar se há `limit()` antes ou se o dataset é uma tabela de domínio com dezenas de linhas.
- Cobrar IaC de recurso que é provisionado em outro repositório — verifique se o README ou o Terraform referencia como `data source`/externo antes de acusar.
- Tratar mudança em arquivo de teste como redução de cobertura sem rodar o comando.
- Confundir arquivo renomeado (`git diff -M` mostra como R) com reescrita completa.
- Ignorar `.tfvars`, `Makefile`, `Dockerfile`, `buildspec.yml`, `.github/workflows/` — mudança de pipeline e de imagem base é tão crítica quanto código.
