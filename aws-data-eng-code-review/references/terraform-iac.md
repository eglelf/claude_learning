# Checklist — Terraform / IaC

O risco aqui é assimétrico: um erro de código quebra uma execução; um erro de IaC destrói recurso com estado. Priorize a análise de **recriação e destruição**.

## Recriação / destruição de recurso com estado

Alterações que forçam `replace` (destroy + create) em recursos que guardam dado são **BLOQUEADOR** sem plano de migração explícito:

- `aws_dynamodb_table`: mudança de `name`, `hash_key`, `range_key`, tipo de atributo-chave.
- `aws_db_instance` / `aws_rds_cluster`: `identifier`, `engine_version` major, `db_subnet_group_name`, `storage_encrypted`.
- `aws_s3_bucket`: `bucket` (nome), região.
- `aws_glue_catalog_table` / `aws_glue_catalog_database`: `name`, `location`, chave de partição.
- `aws_kinesis_stream`, `aws_msk_cluster`, `aws_elasticache_*`: nome/subnet/engine.
- Remoção de `lifecycle { prevent_destroy = true }` ou adição de `force_destroy = true`. Sempre reportar.
- Mudança de `count` para `for_each` (ou reordenação de lista em `count`): reindexa e recria tudo. BLOQUEADOR.
- Recurso removido do código sem `terraform state rm`/migração declarada: destruição no apply.

Sem `terraform plan` executado, isso é análise estática: reporte como "risco a confirmar com plan", com o atributo e o recurso citados.

## IAM e segurança

- `Action: "*"` ou `Resource: "*"` em policy nova. BLOQUEADOR (exceto casos que a própria AWS exige, ex.: algumas ações de `logs`, que devem estar restritas ao log group).
- Policy inline ampla onde existe policy gerenciada mínima; role compartilhada entre serviços com necessidades distintas.
- `assume_role_policy` com principal amplo (conta inteira, `"*"`, sem `Condition` de `sts:ExternalId` quando cross-account).
- Security group com `0.0.0.0/0` em porta de banco/administração. BLOQUEADOR.
- Recurso sem criptografia: S3 sem SSE, RDS sem `storage_encrypted`, DynamoDB sem `server_side_encryption`, SQS/SNS sem KMS, EBS sem encrypt.
- Segredo em `.tfvars` versionado, em `default` de variável ou em `output` sem `sensitive = true`. BLOQUEADOR.
- Backend remoto: state com lock (DynamoDB) e criptografia; state local versionado é BLOQUEADOR.

## Operação e custo

- Retenção de log definida (`aws_cloudwatch_log_group.retention_in_days`) — default é "para sempre" e vira custo permanente. ALTO.
- Alarme/monitoração para o recurso novo (falha de job, DLQ com mensagem, throttling, idade do iterator).
- Tags obrigatórias do time (owner, centro de custo, ambiente, sistema) presentes no recurso novo.
- Nomenclatura por ambiente parametrizada; nome fixo impede promoção dev→hml→prd e causa colisão.
- Provider e módulos com versão pinada (`~>` com limite superior; nunca módulo apontando para branch móvel).
- `depends_on` onde há dependência implícita real; `ignore_changes` usado para esconder drift.
- Valor de ambiente hardcoded (ARN de conta, subnet ID, ID de VPC) no `.tf` em vez de variável/`data source`.

## Coerência código ↔ infraestrutura

- Todo recurso novo referenciado no código Python/SQL existe no IaC do repositório **ou** está declarado como externo (`data source`, documentado no README). Ausência = BLOQUEADOR (deploy quebra em produção).
- Permissão nova exigida pelo código (nova ação em bucket, tabela, secret) refletida na policy da role.
- Variável de ambiente nova consumida pelo código e não declarada no IaC / template de deploy.
- Recurso criado no IaC e não usado por ninguém: custo órfão. MÉDIO.

## Comandos permitidos

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint / checkov -d .        # se disponíveis
```

`plan` somente com credenciais fornecidas pelo usuário e autorização explícita. `apply` e `destroy`: **nunca**.
