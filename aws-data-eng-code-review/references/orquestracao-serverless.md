# Checklist — Lambda, Step Functions, SageMaker Processing, Maestro/Airflow

Fio condutor: **execução distribuída falha e é repetida**. Todo componente aqui precisa responder a "o que acontece quando isso roda duas vezes, ou para no meio?".

## AWS Lambda

- **Idempotência**: SQS, Kinesis, EventBridge e retry do próprio Lambda são *at-least-once*. Handler que insere/soma/publica sem chave de idempotência (condition expression, chave natural, tabela de controle) duplica dado. BLOQUEADOR quando o efeito é persistente.
- **Falha parcial em batch**: consumo de SQS/Kinesis sem `ReportBatchItemFailures` reprocessa o lote inteiro por causa de uma mensagem. ALTO.
- **DLQ / destino de falha** em invocação assíncrona: ausência significa perda silenciosa de evento. BLOQUEADOR quando o evento é a única fonte.
- **Timeout e memória**: timeout menor que o P99 da chamada externa; memória subdimensionada (CPU é proporcional à memória). Timeout do Lambda deve ser menor que o `VisibilityTimeout` da fila.
- **Cliente boto3/conexão criado dentro do handler** em vez do escopo do módulo: perde reuso de conexão e aumenta latência.
- **Imports pesados** (pandas, pyspark, numpy) para tarefa trivial: cold start e limite de pacote.
- **Payload**: 6MB síncrono / 256KB assíncrono. Passar dado grande em vez de ponteiro S3.
- **Concorrência reservada** quando o downstream é RDS ou API com limite — sem isso o Lambda derruba o dependente. ALTO.
- **Lambda → RDS sem RDS Proxy**: esgota conexões sob escala. ALTO/BLOQUEADOR.
- **Configuração** via variável de ambiente em texto claro para credencial (deve ser Secrets Manager/SSM SecureString).
- **Logging** estruturado com identificador de correlação (`requestId`, `execution_id`); sem `print`; sem PII no log.

## Step Functions

- `Retry` com `BackoffRate`, `MaxAttempts` e `IntervalSeconds` nas tarefas que chamam serviço externo; `Catch` roteando para estado de falha que notifica/alarma. Estado que grava dado sem `Catch` mascara falha. BLOQUEADOR.
- `TimeoutSeconds` em toda tarefa longa: sem isso, execução pendurada consome cota e atrasa a janela.
- Limite de 256KB no payload entre estados: dado trafegando inteiro em vez de referência S3. ALTO.
- `Map` com `MaxConcurrency` ilimitado sobre downstream limitado (RDS, API, Glue com cota de jobs concorrentes). ALTO.
- Integração `.sync` vs polling manual: `.sync` já espera o job; polling caseiro costuma perder o estado final.
- Reexecução: a máquina inteira é idempotente? Estados intermediários que já gravaram serão reexecutados no retry.
- Escolha por `Choice` cobrindo o caso default (`Default`), senão a execução falha com `States.NoChoiceMatched`.
- Definição versionada no repositório (ASL/Terraform) e não editada no console.

## SageMaker Processing

- `instance_type`/`instance_count` coerentes com o volume; job de dado pequeno em instância grande é desperdício recorrente.
- `max_runtime_in_seconds` definido.
- Uso de Spot com checkpoint/tolerância a interrupção quando aplicável.
- Imagem do container pinada por digest/tag imutável, não `latest`.
- Entrada/saída S3 explícitas; código do job não escrevendo em caminho local que se perde ao final.
- `network_config` (VPC, isolamento, criptografia inter-container) para dado sensível.
- Tags de custo/owner.

## Maestro / Airflow / orquestração corporativa

- Dependências entre jobs declaradas na ferramenta — não implícitas por horário ("roda 10 min depois porque geralmente dá tempo"). ALTO.
- Parâmetro de **data lógica** (data de referência do processamento) separado da data de execução; reprocessamento de D-3 deve produzir o mesmo resultado.
- Política de retry na orquestração coerente com a idempotência do job (retry automático em job não idempotente é BLOQUEADOR).
- Janela/SLA e alarme de atraso; falha que não notifica ninguém é falha descoberta pelo usuário de negócio.
- Catch-up/backfill: comportamento definido ao religar um fluxo parado.
- Mudança de agendamento (cron, fuso) refletida no README e comunicada aos consumidores.
- Concorrência: mesma tarefa disparando duas execuções simultâneas sobre a mesma partição.

## Eventos e mensageria (SQS, SNS, EventBridge, Kinesis)

- Fila com DLQ e `maxReceiveCount` definido.
- Ordenação: FIFO exigido pela regra de negócio e implementado como FIFO?
- Contrato do evento versionado; consumidor tolerante a campo novo.
- Kinesis: número de shards, chave de partição sem hot shard, checkpoint/iterator age monitorado.
- Mensagem venenosa não pode travar o processamento indefinidamente.
