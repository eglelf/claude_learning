# Checklist — Python, dependências e testes

## Tratamento de erro (fonte comum de BLOQUEADOR)

- `except Exception: pass`, `except: continue`, log de erro sem re-raise em fluxo que grava dado: o job "passa" sem ter feito o trabalho. BLOQUEADOR.
- Exceção capturada larga demais escondendo erro de programação.
- Código de saída: falha que não propaga status ≠ 0 faz a orquestração marcar sucesso.
- Retry sem backoff, sem limite, ou aplicado a erro não transitório (validação, permissão).
- Recurso não liberado (conexão, arquivo, sessão Spark) fora de `with`/`finally`.
- Erro engolido em laço de processamento por registro sem contabilizar rejeitados nem falhar acima de um limiar.

## Configuração e parametrização

- ARN, bucket, nome de tabela, conta AWS, endpoint, e-mail e agendamento hardcoded no código: MÉDIO por padrão, BLOQUEADOR quando aponta para ambiente diferente do alvo de deploy.
- Segredo em código, em default de parâmetro ou em arquivo versionado: BLOQUEADOR.
- Mesma configuração duplicada em vários pontos, com risco de divergirem.
- Parâmetro novo sem valor default e sem documentação: quebra a execução existente.

## Logging e observabilidade

- `print` em vez de `logging` em código de produção.
- Log sem identificador de correlação (execution id, job run id, chave de negócio) — inviabiliza diagnóstico.
- **PII/dado sensível em log**: CPF, conta, cartão, nome completo, e-mail, payload cru. BLOQUEADOR em contexto financeiro.
- Log de volume proibitivo (uma linha por registro em milhões) — custo de CloudWatch.
- Métrica/contador do que importa: linhas lidas, gravadas, rejeitadas, duração.

## Estrutura e legibilidade

- Regra de negócio acoplada a IO (leitura/escrita dentro da função de transformação) — impede teste unitário e infla a necessidade de mock.
- Função muito longa com múltiplas responsabilidades; complexidade ciclomática alta em regra crítica.
- Tipagem em interface pública e docstring no ponto de entrada do job.
- Código morto, import não usado, TODO/FIXME introduzido no diff.
- Divergência do padrão estabelecido do time (estrutura `app/`, nomes, camadas): MÉDIO.

## Dependências

- Versão não pinada em produção (`boto3` sem limite superior) ou pin excessivamente rígido sem motivo.
- Dependência nova: é necessária? já existe equivalente no projeto? tem manutenção ativa? licença compatível?
- Divergência entre `requirements.txt`, `pyproject.toml` e o que o job realmente instala.
- Biblioteca com CVE conhecida ou versão descontinuada.
- Dependência pesada adicionada a Lambda (limite de pacote e cold start).

## Testes

Cobertura é o piso, não o objetivo. Gate do time:

```bash
pytest -q --cov=app --ignore=app/tests/test_integration.py app/tests
```

Mínimo **90%**. Abaixo disso: BLOQUEADOR.

Avalie também a **qualidade** — cobertura alta com teste fraco é pior que cobertura honesta:

- Teste sem `assert`, com `assert True`, ou que apenas verifica se a função não lança exceção.
- Mock que substitui a própria lógica sendo testada (testa o mock, não o código).
- **Configuração de cobertura alterada no diff** (`omit`, `exclude_lines`, `fail_under`, `--cov` apontando para pacote menor): sinal de inflar o número. Reporte sempre, com o diff do arquivo de config.
- Caminho de erro sem teste: entrada vazia, schema divergente, falha do serviço externo, duplicata, timeout.
- Regra de negócio nova ou alterada sem teste correspondente, mesmo com cobertura global ≥ 90%: ALTO.
- Teste não determinístico: `datetime.now()` sem congelar, `sleep`, dependência de ordem de execução, chamada de rede real.
- Chamadas AWS mockadas com `moto` ou `botocore.stub`, não com mock genérico que aceita qualquer coisa.
- `test_integration.py` fora do gate: existe, está coerente com a mudança e é executável no pipeline de integração?
- Fixtures/dados de teste com dado real de cliente: BLOQUEADOR (LGPD).
