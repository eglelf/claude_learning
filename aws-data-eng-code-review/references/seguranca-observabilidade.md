# Checklist — Segurança, dado sensível, observabilidade e custo

Contexto de instituição financeira: rastreabilidade e proteção de dado pessoal têm peso regulatório, não só técnico.

## Segredos e credenciais

Padrões a procurar no diff (`git diff` completo, incluindo arquivos de config, teste e notebook):

```
AKIA[0-9A-Z]{16}          ASIA[0-9A-Z]{16}
aws_secret_access_key      -----BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY-----
password|passwd|senha|pwd  token|api[_-]?key|client[_-]?secret
jdbc:[a-z]+://[^ ]*:[^ ]*@ mongodb(\+srv)?://[^ ]*:[^ ]*@
```

Também: `.env`, `.pem`, `.p12`, `credentials`, `id_rsa` versionados; segredo em `.tfvars`, em `default` de variável Terraform, em variável de ambiente de Lambda/Glue, em fixture de teste.

Segredo commitado é **BLOQUEADOR** e exige rotação — mesmo que removido em commit posterior, ele permanece no histórico. Registre isso no relatório.

**No relatório, mascare**: cite `app/config.py:42` e `AKIA****REDACTED`, nunca o valor.

## Dado pessoal e sensível (LGPD)

- CPF/CNPJ, nome, conta, agência, cartão, e-mail, telefone, endereço, dado de saúde ou biométrico em log, em mensagem de erro, em nome de arquivo ou em dado de teste versionado. BLOQUEADOR.
- Dado sensível gravado em bucket/tabela sem criptografia ou fora da zona de classificação correta.
- Mascaramento/tokenização esperado pela política e ausente no caminho novo.
- Cópia de dado produtivo para ambiente de desenvolvimento.
- Retenção: dado pessoal sem política de expiração definida.
- Compartilhamento de dado com destino novo (bucket de outra conta, API externa, e-mail): exige justificativa e controle explícito.

## Permissões e rede

- Princípio do menor privilégio na role usada pelo componente novo.
- Credencial de longa duração (access key) onde caberia role/`AssumeRole`.
- Acesso cross-account sem condição restritiva.
- Recurso privado exposto: endpoint público, security group aberto, bucket sem *block public access*.
- Tráfego para serviço AWS saindo pela internet quando há VPC endpoint disponível (custo + exposição).

## Observabilidade

- Falha do componente novo gera alarme para alguém — não basta aparecer no CloudWatch.
- Log estruturado com correlação ponta a ponta (id de execução propagado entre Lambda → Step Functions → Glue).
- Métricas de negócio, não só de infraestrutura: linhas lidas/gravadas/rejeitadas, atraso da partição, divergência de contagem.
- Nível de log adequado (`DEBUG` ligado em produção é custo e vazamento potencial).
- Rastreabilidade: dá para responder "de onde veio essa linha e qual execução a gerou?".
- Retenção de log definida e compatível com a exigência de auditoria.

## Custo

- Scan de tabela inteira em rotina recorrente (Athena por TB, Glue por DPU-hora, DynamoDB por RCU).
- Dimensionamento excessivo: workers/DPUs/instâncias muito acima do volume, `instance_count` fixo alto.
- Cluster/endpoint ligado 24/7 para carga batch.
- Log sem retenção, S3 sem lifecycle, snapshot sem expiração.
- Small files inflando requisições S3 e tempo de listagem.
- Reprocessamento full onde caberia incremental.

Custo entra como ALTO quando o aumento é recorrente e relevante; MÉDIO quando é pontual. Sempre indique a ordem de grandeza que sustenta a classificação (volume, frequência), sem inventar valor em reais.
