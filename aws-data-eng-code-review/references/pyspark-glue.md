# Checklist — PySpark / AWS Glue / EMR

Ordem de leitura: escrita de dados → shuffle/join → leitura → configuração do job → testes.
A pergunta guia é sempre a mesma: *no volume real de produção, isso termina, termina no tempo, e termina com o dado certo?*

## Escrita e integridade do dado (maior fonte de BLOQUEADOR)

- `mode("overwrite")` em tabela particionada **sem** `spark.sql.sources.partitionOverwriteMode=dynamic`: apaga todas as partições. BLOQUEADOR.
- `overwrite` apontando para o caminho pai da partição, ou path montado por concatenação de string que pode resolver para a raiz.
- Job re-executável? Rerun após falha parcial duplica linha (`append` sem chave/dedup/bookmark) ou perde histórico. Espera-se `MERGE INTO`, `INSERT OVERWRITE` por partição, deduplicação por chave+`updated_at` ou job bookmark habilitado. Sem nada disso: BLOQUEADOR.
- Escrita sem controle de partição gerando *small files* (milhares de arquivos < 10MB): degrada leitura e custo. `coalesce`/`repartition` por chave de partição ou `maxRecordsPerFile`. ALTO.
- `coalesce(1)` em dataset grande: força uma task única, OOM garantido acima de alguns GB. BLOQUEADOR se o volume justificar.
- Ordem `write` → `catálogo`: partição gravada mas não registrada (falta `MSCK`, `partition projection` ou `saveAsTable`) deixa o dado invisível para o consumidor.
- Falha silenciosa: `try/except` em volta da escrita que segue o fluxo, ou job que termina com exit 0 sem ter gravado nada (sem validação de contagem/`isEmpty`).
- Mudança de schema de saída (coluna removida, renomeada, tipo alterado, ordem em CSV) sem versionamento nem aviso ao consumidor: BLOQUEADOR.

## Shuffle, join e skew

- Join sem `broadcast()` quando um lado é pequeno (< ~50–100MB) — ou o inverso: `broadcast` de dataset grande, que estoura o driver. Confira o `autoBroadcastJoinThreshold` do job.
- Skew conhecido (chave nula, chave default como `"0000"`, cliente concentrador): esperado salting, `spark.sql.adaptive.skewJoin.enabled` ou filtro prévio. ALTO.
- `spark.sql.shuffle.partitions` no default 200 com volume alto (ou AQE desabilitado sem motivo). ALTO.
- Join sem condição de partição/filtro, produzindo produto cartesiano parcial.
- Múltiplas leituras do mesmo DataFrame recomputando a cadeia inteira: `cache()`/`persist()` ausente onde há reuso real, ou `cache()` presente onde não há reuso (custo de memória à toa) e sem `unpersist`.

## Ações caras no driver

- `collect()`, `toPandas()`, `take` grande sem `limit()` prévio ou sobre dataset não delimitado: OOM no driver. BLOQUEADOR quando o dataset é o fato/movimento; irrelevante em tabela de domínio pequena — verifique.
- `count()` dentro de loop ou usado só para log; `show()` em produção.
- Loop Python iterando linhas (`for row in df.collect()`) em vez de transformação distribuída.
- Escrita/leitura dentro de laço por partição de data quando `partitionBy` resolveria em uma passada.

## Leitura

- `inferSchema` em produção: custo de scan extra e tipo instável entre execuções. Schema explícito (`StructType`) ou catálogo. ALTO.
- Falta de *predicate pushdown* / *partition pruning*: leitura da tabela inteira e filtro depois. Em Glue: `push_down_predicate` / `catalogPartitionPredicate`. ALTO/BLOQUEADOR conforme volume e custo.
- `select("*")` quando só algumas colunas são usadas (Parquet/ORC perdem *column pruning*).
- Formato de entrada CSV/JSON onde já existe camada colunar disponível.
- Data de referência: uso de `current_date()` em vez do parâmetro de data lógica do job — impede reprocessamento correto. ALTO.

## Configuração do job Glue

- Worker type e número de workers coerentes com o volume; `--enable-auto-scaling`.
- Timeout e `max retries` definidos; retry > 0 em job não idempotente é perigoso.
- `--enable-metrics`, `--enable-continuous-cloudwatch-log`, Spark UI para diagnóstico.
- Job bookmark: habilitado, desabilitado ou resetado — coerente com a estratégia de reprocessamento.
- Concorrência máxima > 1 em job que escreve na mesma partição: corrida de escrita. BLOQUEADOR.
- Versão do Glue/Spark alterada no diff: valida compatibilidade de biblioteca e mudança de comportamento (ex.: parsing de data no Spark 3).
- `--additional-python-modules` / wheels: versões pinadas.
- Conexão/VPC quando acessa RDS ou recurso privado.

## Formatos transacionais (Iceberg / Delta / Hudi)

- `MERGE INTO` com chave que garante unicidade real (senão duplica ou apaga demais).
- Rotina de compactação e expiração de snapshots definida; sem isso a tabela degrada e o custo cresce.
- Configuração de catálogo/warehouse consistente com o ambiente.
- Evolução de schema explícita, não implícita via `mergeSchema` em produção.

## Testes de código Spark

- Fixture de `SparkSession` local reaproveitada por sessão (não uma por teste).
- Testes cobrem transformação (regra de negócio) e não só o wiring de leitura/escrita.
- Comparação de DataFrame com ordenação determinística.
- Caminho de erro testado: entrada vazia, coluna ausente, tipo divergente, duplicata.
