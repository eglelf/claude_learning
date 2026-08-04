# Checklist — Athena, S3/Glue Catalog, DynamoDB, RDS e SQL

## Athena / SQL analítico

- **Filtro de partição ausente**: consulta varre a tabela inteira. Custo por TB escaneado e tempo. ALTO; BLOQUEADOR em tabela de movimento com histórico longo em rotina diária.
- `SELECT *` em tabela colunar larga: anula *column pruning*.
- Filtro aplicado sobre coluna derivada (`CAST(dt AS date) = ...`, `substr(dt,1,7)`) impede *partition pruning* — comparar direto com a coluna de partição.
- `partition projection` ou `MSCK REPAIR`/`ALTER TABLE ADD PARTITION` definidos para partição nova aparecer; `MSCK` em tabela com milhares de partições é lento e caro.
- CTAS/`INSERT INTO` gerando arquivos pequenos ou sem `partitioned_by`/`bucketed_by` adequados.
- Workgroup com limite de bytes escaneados e local de resultado definidos.
- Joins com tabela grande à esquerda; ordem e filtro antecipado importam.
- Formato final: Parquet/ORC com compressão (Snappy/ZSTD) — CSV/JSON em camada consumida é achado.
- `WHERE` ausente em `DELETE`/`UPDATE` (Iceberg) ou DDL destrutivo (`DROP`, `MSCK` com `TABLE` errada). BLOQUEADOR.

## S3 e layout

- Layout de partição estável (`dt=YYYY-MM-DD` ou `ano=/mes=/dia=`) e coerente com o padrão do time.
- Cardinalidade da partição: partição por hora em volume baixo gera milhares de arquivos minúsculos; partição por ano impede pruning útil.
- Criptografia (SSE-KMS para dado sensível), bloqueio de acesso público, política de bucket sem `Principal: "*"`.
- Versionamento e lifecycle (transição/expiração) definidos — custo cresce em silêncio.
- Caminho montado por concatenação sem sanitização, podendo escrever fora do prefixo esperado.
- Bucket/prefixo hardcoded no código em vez de parâmetro por ambiente. MÉDIO, ou BLOQUEADOR se aponta para conta/ambiente errado.

## Glue Data Catalog

- Tipos declarados corretamente (`string` para valor monetário, `double` para dinheiro em vez de `decimal`: achado real).
- Evolução de schema: coluna adicionada no fim vs no meio (quebra leitura posicional).
- Tabela x view, `SerDe` e `location` coerentes com o que o job escreve.
- Alteração de `location` ou de chave de partição em tabela existente: dado antigo fica órfão. BLOQUEADOR sem plano de migração.

## DynamoDB

- Chave de partição com boa distribuição; chave de baixa cardinalidade (data, status, tipo fixo) cria hot partition e throttling. ALTO.
- `scan` em tabela grande em rotina recorrente — deve ser `query` com chave/GSI. ALTO.
- GSI: projeção adequada (`KEYS_ONLY`/`INCLUDE` vs `ALL`), custo de escrita duplicada, throttling do índice derrubando a tabela base.
- Capacidade: on-demand vs provisionada com auto scaling — coerente com o padrão de carga.
- Idempotência via `ConditionExpression` (`attribute_not_exists`) em escrita que pode ser repetida.
- Paginação tratada (`LastEvaluatedKey`) — código que lê só a primeira página perde dado silenciosamente. BLOQUEADOR.
- `BatchWriteItem`: `UnprocessedItems` reprocessados com backoff; ignorar isso perde item. BLOQUEADOR.
- Limite de 400KB por item; TTL configurado quando há dado transitório.
- Transações e escritas condicionais onde há concorrência real.

## RDS / bancos relacionais

- **SQL montado por f-string/concatenação com input externo**: injeção. BLOQUEADOR.
- Pool de conexões e fechamento garantido (`with`/`finally`); conexão por linha processada.
- Transação: `commit`/`rollback` explícitos; operação em lote sem transação deixando estado parcial.
- Inserção linha a linha em volume alto — `executemany`/`COPY`/bulk. ALTO.
- Índice existente para a nova consulta introduzida; `EXPLAIN` mencionado ou índice criado na migração.
- Migração de schema versionada (Alembic/Flyway), reversível e compatível com a versão anterior da aplicação (deploy não é atômico). Coluna `NOT NULL` sem default em tabela grande trava a tabela. BLOQUEADOR.
- `statement_timeout`/`lock_timeout` para não segurar tabela indefinidamente.
- Credencial via Secrets Manager com rotação, não em variável de ambiente estática.
- Consulta N+1 dentro de laço.

## Qualidade do dado (transversal)

- Validação de entrada antes de processar (contagem, schema, nulos em coluna-chave, janela de data esperada).
- Regra de negócio de deduplicação explícita, com chave definida.
- Tratamento de fuso horário e de conversão de data — origem em UTC gravada como local (ou o contrário) é achado recorrente.
- Valor monetário em `float` em vez de `decimal`. ALTO em contexto financeiro.
- Registro rejeitado vai para onde? Descartar sem trilha é perda silenciosa de dado.
