#!/usr/bin/env bash
# preparar_review.sh — clona/atualiza o repositório e gera os artefatos do diff.
#
# Uso:
#   bash preparar_review.sh <repo_url_ou_path> <branch_feature> [branch_base] [workspace]
#
# Saída: <workspace>/.review/<repo>/{info.env,commits.txt,arquivos_alterados.txt,
#         diff_stat.txt,diff_completo.patch,dominios.txt}
#
# Não faz commit, push, merge ou qualquer escrita no remoto.

set -uo pipefail

REPO_URL="${1:-}"
BRANCH_FEATURE="${2:-}"
BRANCH_BASE="${3:-main}"
WORKSPACE="${4:-/workspaces}"

if [ -z "$REPO_URL" ] || [ -z "$BRANCH_FEATURE" ]; then
  echo "ERRO: uso: bash preparar_review.sh <repo_url> <branch_feature> [branch_base] [workspace]" >&2
  exit 2
fi

REPO_NAME="$(basename "${REPO_URL%.git}")"
REPO_DIR="$WORKSPACE/$REPO_NAME"
OUT_DIR="$WORKSPACE/.review/$REPO_NAME"
mkdir -p "$OUT_DIR" || { echo "ERRO: sem permissão de escrita em $WORKSPACE" >&2; exit 2; }

# ---------------------------------------------------------------- clone/fetch
if [ -d "$REPO_DIR/.git" ]; then
  echo "[info] repositório já existe em $REPO_DIR — atualizando"
  if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
    echo "AVISO: working tree com alterações locais não commitadas. Elas NÃO serão descartadas." >&2
    git -C "$REPO_DIR" status --porcelain >&2
  fi
  git -C "$REPO_DIR" fetch --prune --tags origin || { echo "ERRO: falha no fetch" >&2; exit 3; }
else
  echo "[info] clonando em $REPO_DIR"
  git clone --no-single-branch "$REPO_URL" "$REPO_DIR" || { echo "ERRO: falha no clone (rede/credencial/URL)" >&2; exit 3; }
fi

GIT=(git -C "$REPO_DIR")

resolver_ref() {   # aceita 'branch', 'origin/branch' ou SHA
  local ref="$1"
  for cand in "origin/$ref" "$ref"; do
    if "${GIT[@]}" rev-parse --verify --quiet "$cand^{commit}" >/dev/null; then
      "${GIT[@]}" rev-parse "$cand^{commit}"
      return 0
    fi
  done
  return 1
}

HEAD_SHA="$(resolver_ref "$BRANCH_FEATURE")" || { echo "ERRO: branch '$BRANCH_FEATURE' não encontrada" >&2; exit 4; }
BASE_SHA="$(resolver_ref "$BRANCH_BASE")"    || { echo "ERRO: branch base '$BRANCH_BASE' não encontrada" >&2; exit 4; }
MERGE_BASE="$("${GIT[@]}" merge-base "$BASE_SHA" "$HEAD_SHA")" || { echo "ERRO: branches sem ancestral comum" >&2; exit 4; }

# working tree no commit da feature (necessário para rodar a suíte de testes)
"${GIT[@]}" checkout --detach --quiet "$HEAD_SHA" || { echo "ERRO: checkout falhou (alterações locais?)" >&2; exit 5; }

# ------------------------------------------------------------------ artefatos
RANGE="$MERGE_BASE..$HEAD_SHA"

"${GIT[@]}" log --no-merges --date=short \
  --pretty='%h | %ad | %an | %s' "$RANGE" > "$OUT_DIR/commits.txt"

"${GIT[@]}" diff -M --name-status "$MERGE_BASE" "$HEAD_SHA" > "$OUT_DIR/arquivos_alterados.txt"
"${GIT[@]}" diff -M --stat "$MERGE_BASE" "$HEAD_SHA"        > "$OUT_DIR/diff_stat.txt"
"${GIT[@]}" diff -M --unified=5 "$MERGE_BASE" "$HEAD_SHA"   > "$OUT_DIR/diff_completo.patch"

N_ARQ=$(grep -cve '^$' "$OUT_DIR/arquivos_alterados.txt" 2>/dev/null || echo 0)
N_COMMITS=$(grep -cve '^$' "$OUT_DIR/commits.txt" 2>/dev/null || echo 0)
LINHAS=$(tail -n1 "$OUT_DIR/diff_stat.txt" 2>/dev/null | sed 's/^ *//')
README_ALT=$(grep -Eiq '(^|/)readme\.md' "$OUT_DIR/arquivos_alterados.txt" && echo sim || echo nao)

# --------------------------------------------------- classificação de domínio
ARQS="$(cut -f2- "$OUT_DIR/arquivos_alterados.txt")"
detecta() {  # <regex_path> <regex_conteudo|-> <rotulo>
  local rp="$1" rc="$2" rotulo="$3"
  if echo "$ARQS" | grep -Eiq "$rp"; then echo "$rotulo"; return; fi
  if [ "$rc" != "-" ] && grep -Eiq "$rc" "$OUT_DIR/diff_completo.patch"; then echo "$rotulo"; fi
}
{
  detecta '\.(py)$' 'pyspark|SparkSession|awsglue|GlueContext|DynamicFrame|spark\.(read|sql)' 'pyspark-glue'
  detecta 'glue|emr' 'aws_glue_job|glueetl|iceberg|delta|hudi' 'pyspark-glue'
  detecta 'lambda' 'lambda_handler|aws_lambda_function|powertools' 'lambda'
  detecta 'step.?function|state.?machine|\.asl\.(json|yaml)' 'StartExecution|aws_sfn_state_machine|"States"' 'step-functions'
  detecta 'maestro|airflow|dag' 'DAG\(|@dag|maestro' 'orquestracao'
  detecta 'sagemaker|processing' 'ProcessingJob|sagemaker\.' 'sagemaker'
  detecta '\.(sql|hql)$' 'CREATE TABLE|INSERT INTO|MSCK REPAIR|athena' 'athena-sql'
  detecta 'dynamo' 'dynamodb|put_item|query\(|aws_dynamodb_table' 'dynamodb'
  detecta 'rds|migrations?/' 'psycopg|sqlalchemy|pymysql|aws_rds|ALTER TABLE' 'rds'
  detecta '\.(tf|tfvars)$|terraform' 'resource "aws_|module "' 'terraform'
  detecta 'tests?/' 'def test_|pytest|moto' 'testes'
  detecta 'readme\.md$' '-' 'documentacao'
  detecta '\.github/workflows|buildspec|Jenkinsfile|Dockerfile|Makefile' 'docker build|deploy' 'ci-cd'
  detecta 'requirements.*\.txt$|pyproject\.toml|poetry\.lock|setup\.(py|cfg)' '-' 'dependencias'
} | sort -u > "$OUT_DIR/dominios.txt"

cat > "$OUT_DIR/info.env" <<EOF
REPO_NAME=$REPO_NAME
REPO_URL=$REPO_URL
REPO_DIR=$REPO_DIR
OUT_DIR=$OUT_DIR
BRANCH_FEATURE=$BRANCH_FEATURE
BRANCH_BASE=$BRANCH_BASE
HEAD_SHA=$HEAD_SHA
BASE_SHA=$BASE_SHA
MERGE_BASE=$MERGE_BASE
N_COMMITS=$N_COMMITS
N_ARQUIVOS=$N_ARQ
DIFF_STAT_TOTAL=$LINHAS
README_ALTERADO=$README_ALT
DATA_REVIEW=$(date -u '+%Y-%m-%d %H:%M UTC')
EOF

echo "----- resumo -----"
cat "$OUT_DIR/info.env"
echo "----- domínios detectados (heurística — confirmar na leitura) -----"
cat "$OUT_DIR/dominios.txt"
