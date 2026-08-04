# Template — resultado_codereview.md

Escreva em `<workspace>/resultado_codereview.md` (default `/workspaces/resultado_codereview.md`).
Siga a estrutura abaixo. Seção sem conteúdo: mantenha o título e escreva "Nenhum." — não remova a seção.
Substitua tudo entre `<>`. Sem preâmbulo, sem conclusão motivacional.

---

```markdown
# Code Review — <repositório>

**Branch analisada:** `<feature>` → **base:** `<base>`
**Commits:** `<merge_base_curto>` .. `<head_curto>` (<N> commits, <N> arquivos, <+X/-Y> linhas)
**Data:** <YYYY-MM-DD HH:MM UTC>
**Domínios:** <PySpark/Glue, Terraform, Lambda, ...>

## 1. Veredito

**<APROVADO | APROVADO COM RESSALVAS | REPROVADO>**

<2 a 4 linhas: o que a mudança faz e o que sustenta o veredito.>

| Severidade | Qtd |
|---|---|
| Bloqueador | <n> |
| Alto | <n> |
| Médio | <n> |
| Baixo | <n> |

## 2. Portões de qualidade

| Gate | Resultado | Evidência |
|---|---|---|
| Testes unitários | <PASS / FAIL / NÃO VERIFICADO> | <n passed, n failed — saída do pytest> |
| Cobertura ≥ 90% | <PASS / FAIL — X.X%> | `<comando executado>` |
| README atualizado | <PASS / FAIL / N/A> | <o que mudou e não está documentado> |
| Sem segredos versionados | <PASS / FAIL> | <arquivo:linha, valor mascarado> |
| IaC coerente com o código | <PASS / FAIL / N/A> | <recurso e arquivo> |
| `terraform validate` / `fmt -check` | <PASS / FAIL / N/A> | <saída resumida> |

<Se algum gate não pôde ser executado, explique o motivo em uma linha.>

## 3. Bloqueadores

> Impedem o deploy. Precisam ser corrigidos e reavaliados.

### B<n> — <título objetivo>
- **Arquivo:** `<caminho>:<linha>`
- **Evidência:**
  ```<linguagem>
  <trecho mínimo do código>
  ```
- **Risco:** <o que acontece em produção — perda de dado, custo, falha silenciosa, exposição>
- **Correção sugerida:** <ação concreta e verificável>

## 4. Riscos altos

### A<n> — <título>
- **Arquivo:** `<caminho>:<linha>`
- **Risco:** <impacto sob carga ou em falha>
- **Correção sugerida:** <ação>

## 5. Médios e baixos

| # | Sev | Arquivo:linha | Achado | Sugestão |
|---|---|---|---|---|
| M1 | Médio | `<path:linha>` | <achado> | <sugestão> |
| L1 | Baixo | `<path:linha>` | <achado> | <sugestão> |

## 6. Pontos positivos

<Máximo 5 linhas. Só o que é objetivamente bom e vale preservar como padrão.>

## 7. Escopo verificado

**Analisado em profundidade:** <arquivos/áreas>
**Não verificado:** <item — motivo (sem credencial, sem rede, fora do escopo do diff, diff extenso)>

## 8. Comandos executados

```bash
<comando 1>
<comando 2>
```

## 9. Próximos passos

1. <ação — responsável: autor>
2. <ação>
```

---

## Regras de preenchimento

- **Um achado, um problema.** Ocorrências repetidas da mesma causa raiz viram um achado com a lista de arquivos.
- **Título é diagnóstico, não sintoma.** "Overwrite apaga todas as partições da tabela" em vez de "problema na escrita".
- **Correção verificável.** "Adicionar `spark.conf.set('spark.sql.sources.partitionOverwriteMode','dynamic')` antes da escrita em `app/jobs/carga.py:88`" em vez de "melhorar a escrita".
- **Evidência mínima.** Trecho de até ~10 linhas. Não cole o arquivo inteiro nem o diff completo.
- **Sem valor de segredo.** Sempre mascarado.
- **Sem hedge.** Se é bloqueador, afirme. Se é incerto, coloque em "Não verificado" ou rebaixe a severidade — não escreva "pode ser que talvez".
