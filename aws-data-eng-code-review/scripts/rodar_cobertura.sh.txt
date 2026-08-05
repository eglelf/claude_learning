#!/usr/bin/env bash
# rodar_cobertura.sh — roda a suíte de testes e mede cobertura sem sujar o repositório.
#
# Uso:
#   bash rodar_cobertura.sh [workspace] [repo_name] [pacote_alvo] [dir_testes]
# Defaults: /workspaces <detectado> app app/tests
#
# Artefatos: <workspace>/.review/<repo>/{cobertura.txt,coverage.xml}
# venv, cache e .coverage ficam FORA da árvore do repositório.

set -uo pipefail

WORKSPACE="${1:-/workspaces}"
REPO_NAME="${2:-}"

if [ -z "$REPO_NAME" ]; then
  REPO_NAME="$(ls -1 "$WORKSPACE/.review" 2>/dev/null | head -n1)"
  [ -z "$REPO_NAME" ] && { echo "ERRO: informe o repo_name (nada em $WORKSPACE/.review)" >&2; exit 2; }
fi

OUT_DIR="$WORKSPACE/.review/$REPO_NAME"
REPO_DIR="$WORKSPACE/$REPO_NAME"
[ -d "$REPO_DIR" ] || { echo "ERRO: $REPO_DIR não existe" >&2; exit 2; }

PKG="${3:-app}"
TESTS="${4:-app/tests}"
[ -d "$REPO_DIR/$PKG" ]   || echo "AVISO: pacote '$PKG' não existe — estrutura fora do padrão do time" >&2
[ -d "$REPO_DIR/$TESTS" ] || echo "AVISO: diretório de testes '$TESTS' não existe — estrutura fora do padrão do time" >&2

VENV="$OUT_DIR/venv"
export PYTHONDONTWRITEBYTECODE=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
export COVERAGE_FILE="$OUT_DIR/.coverage"
export PYTEST_ADDOPTS="-p no:cacheprovider"

# --system-site-packages: se o container já tem as libs, o review roda mesmo sem rede
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv --system-site-packages "$VENV" || { echo "ERRO: falha ao criar venv" >&2; exit 3; }
fi
PY="$VENV/bin/python"
"$PY" -m pip install -q --upgrade pip >/dev/null 2>&1

# ------------------------------------------------------------- dependências
echo "[info] instalando dependências (venv externo ao repositório)"
INSTALL_LOG="$OUT_DIR/install.log"
: > "$INSTALL_LOG"
for req in requirements.txt requirements-dev.txt requirements-test.txt dev-requirements.txt test-requirements.txt; do
  [ -f "$REPO_DIR/$req" ] && "$PY" -m pip install -q -r "$REPO_DIR/$req" >>"$INSTALL_LOG" 2>&1
done
"$PY" -m pip install -q pytest pytest-cov >>"$INSTALL_LOG" 2>&1

if ! "$PY" -m pytest --version >/dev/null 2>&1; then
  if python3 -m pytest --version >/dev/null 2>&1; then
    echo "AVISO: usando pytest do sistema (instalação no venv falhou — provável ausência de rede)" >&2
    PY="python3"
  else
    echo "ERRO: pytest indisponível. Últimas linhas de $INSTALL_LOG:" >&2
    tail -n 20 "$INSTALL_LOG" >&2
    echo "GATE_TESTES=NAO_VERIFICADO"
    echo "GATE_COBERTURA=NAO_VERIFICADO"
    exit 4
  fi
fi

# ------------------------------------------------------------------ execução
IGNORE_ARG=()
[ -f "$REPO_DIR/$TESTS/test_integration.py" ] && IGNORE_ARG=(--ignore="$TESTS/test_integration.py")

CMD=("$PY" -m pytest -q "--cov=$PKG" "${IGNORE_ARG[@]}" \
     --cov-report=term-missing "--cov-report=xml:$OUT_DIR/coverage.xml" "$TESTS")

echo "[info] comando: ${CMD[*]}"
( cd "$REPO_DIR" && "${CMD[@]}" ) 2>&1 | tee "$OUT_DIR/cobertura.txt"
RC="${PIPESTATUS[0]}"

TOTAL="$(grep -E '^TOTAL' "$OUT_DIR/cobertura.txt" | awk '{print $NF}' | tr -d '%' | tail -n1)"

echo "----------------------------------------"
echo "COMANDO=${CMD[*]}"
echo "EXIT_CODE=$RC"
if [ -n "${TOTAL:-}" ]; then
  echo "COBERTURA_TOTAL=${TOTAL}%"
  awk -v t="$TOTAL" 'BEGIN{ print (t+0 >= 90) ? "GATE_COBERTURA=PASS" : "GATE_COBERTURA=FAIL (<90%)" }'
else
  echo "COBERTURA_TOTAL=indisponivel"
  echo "GATE_COBERTURA=NAO_VERIFICADO"
fi
[ "$RC" -eq 0 ] && echo "GATE_TESTES=PASS" || echo "GATE_TESTES=FAIL"

# resíduos deixados no repositório pela execução
RESIDUO="$(git -C "$REPO_DIR" status --porcelain)"
if [ -n "$RESIDUO" ]; then
  echo "AVISO: a execução deixou resíduos no repositório:"
  echo "$RESIDUO"
fi
exit 0
