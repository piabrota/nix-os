#!/bin/sh
# run.sh: the checks of the thesis toolkit that fit in seconds. Run it with the real command:
#   THESIS=/path/to/bin/thesis sh thesis/test/run.sh
# It needs the toolkit's tools on PATH (jq, pandoc, pdflatex, poppler) and builds one tiny PDF.
# Everything happens in a temporary folder. Prints "N checks, M failed".
# shellcheck disable=SC2016,SC2086
# (SC2016: the sh -c programs in single quotes expand their own arguments; SC2086: test -a lists.)
set -u

: "${THESIS:?set THESIS to the path of the thesis command}"
WRAPPED=$(dirname -- "$THESIS")/.thesis-wrapped
SHARE_SRC=$(dirname -- "$THESIS")/../share/thesis
TOOLPATH=$(sed -n "s/^export PATH='\(.*\)'$/\1/p" "$THESIS" | head -n 1)
export TOOLPATH
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/thesis-test.XXXXXX") || exit 1
trap 'rm -rf "$ROOT"' EXIT
export THESIS_HOME=$ROOT/home THESIS_OUTBOX=$ROOT/outbox
mkdir -p "$THESIS_HOME"
N=0
FAILED=0

# t <name> <command...>: passes when the command succeeds.
t() {
  _name=$1
  shift
  N=$((N + 1))
  if "$@" >"$ROOT/out.txt" 2>&1; then
    echo "ok   $_name"
  else
    FAILED=$((FAILED + 1))
    echo "FAIL $_name"
    sed 's/^/     /' "$ROOT/out.txt" | head -n 12
  fi
}
# r <name> <command...>: passes when the command FAILS (a refusal).
r() {
  _name=$1
  shift
  N=$((N + 1))
  if "$@" >"$ROOT/out.txt" 2>&1; then
    FAILED=$((FAILED + 1))
    echo "FAIL $_name (it was accepted)"
    sed 's/^/     /' "$ROOT/out.txt" | head -n 6
  else
    echo "ok   $_name"
  fi
}
has() { grep -Fq -- "$2" "$1"; }
hasnot() { ! grep -Fq -- "$2" "$1"; }

P=$THESIS_HOME/projects/sample

# --- names
r "slug ../x is refused" "$THESIS" new ../x
r "slug with a space is refused" "$THESIS" new "a b"
r "slug with a leading - is refused" "$THESIS" new -- -x
r "slug with a slash is refused" "$THESIS" new a/b
t "a good slug is accepted" "$THESIS" new sample
r "a second new of the same slug is refused" "$THESIS" new sample
r "section id ../x is refused" "$THESIS" lint sample ../x
r "section id with a space is refused" "$THESIS" lint sample "a b"
r "an unknown section is refused" "$THESIS" lint sample nosuch
r "seat name with a slash is refused" "$THESIS" fetch sample --as ../evil

# --- fetch: two parallel callers get different sections
"$THESIS" new par >/dev/null 2>&1
( "$THESIS" fetch par --as writer-a >"$ROOT/fa.txt" 2>&1 ) &
( "$THESIS" fetch par --as writer-b >"$ROOT/fb.txt" 2>&1 ) &
( "$THESIS" fetch par --as writer-c >"$ROOT/fc.txt" 2>&1 ) &
wait
SA=$(sed -n 's/^section: *\([A-Za-z0-9_-]*\).*/\1/p' "$ROOT/fa.txt")
SB=$(sed -n 's/^section: *\([A-Za-z0-9_-]*\).*/\1/p' "$ROOT/fb.txt")
SC=$(sed -n 's/^section: *\([A-Za-z0-9_-]*\).*/\1/p' "$ROOT/fc.txt")
t "three parallel fetches each got a section" test -n "$SA" -a -n "$SB" -a -n "$SC"
t "the three sections differ" test "$SA" != "$SB" -a "$SA" != "$SC" -a "$SB" != "$SC"
t "a second fetch by the same seat resumes its section" sh -c '"$0" fetch par --as writer-a | grep -q "^section: *'"$SA"'"' "$THESIS"
r "fetch of a section claimed by another seat is refused" "$THESIS" fetch par "$SA" --as writer-b
t "release by the holder works" "$THESIS" release par "$SA" --as writer-a
t "a stale claim does not exist after release" test ! -f "$THESIS_HOME/projects/par/claims/$SA.claim"

# --- the sample project: a tiny thesis with one real section
jq '.title = "Previsão de ondas e portes para GPU" | .title_en = "Wave forecasting and GPU ports"
  | .author = "Autora Teste" | .author_ref = "TESTE, Autora" | .advisor = "Prof. Orientador Teste, D.Sc."
  | .sections |= map(.status = "omit")
  | .sections |= map(if .id == "resumo" then .status = "todo" | .target_words = 40 | .keywords = ["ondas","GPU","Fortran"] else . end)
  | .sections |= map(if .id == "introducao" then .target_words = 120 else . end)' "$P/thesis.json" >"$ROOT/t.json" && cp "$ROOT/t.json" "$P/thesis.json"
cat >"$P/sections/resumo.md" <<'EOF'
A previsão de ondas depende de modelos caros. Este texto de teste descreve um porte para GPU que reproduz os bits do código em Fortran, medido em uma grade pequena.
EOF
t "lint passes on a plain resumo" "$THESIS" lint sample resumo
"$THESIS" fetch sample resumo --as writer-a >/dev/null 2>&1
printf '\n**[AUTHOR: ask what the author measured]**\n' >>"$P/sections/resumo.md"
r "submit refuses a section with an **[AUTHOR: placeholder" "$THESIS" submit sample resumo --as writer-a
t "the refusal names the placeholder" sh -c '"$0" lint sample resumo | grep -q placeholder' "$THESIS"
printf '%s\n' 'A previsão de ondas depende de modelos caros. Este texto de teste descreve um porte para GPU que reproduz os bits do código em Fortran, medido em uma grade pequena.' >"$P/sections/resumo.md"
r "submit refuses when nobody claimed the section (another seat)" "$THESIS" submit sample resumo --as writer-b
t "submit hands in a clean section" "$THESIS" submit sample resumo --as writer-a
r "a writer may not judge a section (verdict by the author)" "$THESIS" verdict sample resumo accept --by writer-a
r "accept needs the reviewer's own review file" "$THESIS" verdict sample resumo accept --by reviewer
printf 'Findings: none. Gates read.\n' >"$P/review/resumo.review.md"
t "verdict accept records the hash" "$THESIS" verdict sample resumo accept --by reviewer
t "the section is accepted" sh -c '"$0" sections sample | grep -q "resumo .* accepted"' "$THESIS"

# --- build, hostile text, raw TeX
cat >"$P/sections/introducao.md" <<'EOF'
# Teste de caracteres

Texto hostil: 100% \write18{id} e \input{/etc/passwd} & $ # _ { } ~ ^ ação, coração e açúcar.

Mais um parágrafo com `código` e **negrito** e *itálico*, para o teste.
EOF
t "hostile characters build" "$THESIS" build-section sample introducao
t "the fragment has the backslash escaped" has "$P/build/introducao.tex" 'textbackslash'
t "no \\input{/etc/passwd} reaches the TeX file" hasnot "$P/build/introducao.tex" '\input{/etc/passwd}'
t "no \\write18 command reaches the TeX file" sh -c '! grep -E "^[^%]*\\\\write18" "$0"' "$P/build/introducao.tex"
t "the preview PDF exists" test -s "$P/build/introducao.preview.pdf"
printf '%s\n' '# Math' '' 'Uma conta $\input{/etc/passwd}$ no texto.' >"$P/sections/introducao.md"
r "a TeX macro that is not on the math list is refused" "$THESIS" build-section sample introducao
printf '%s\n' '# Math' '' 'Uma conta $\write18{id}$ no texto.' >"$P/sections/introducao.md"
r "\\write18 in math is refused" "$THESIS" build-section sample introducao
printf '%s\n' '# Math' '' 'Uma conta $x^2 + \frac{a}{b}$ no texto.' >"$P/sections/introducao.md"
t "plain math builds" "$THESIS" build-section sample introducao
printf '%s\n' '# Emoji' '' 'Um texto com 😀 dentro.' >"$P/sections/introducao.md"
r "an emoji is refused with a clear line" "$THESIS" lint sample introducao
t "the refusal names the character" sh -c '"$0" build-section sample introducao 2>&1 | grep -q "cannot set"' "$THESIS"
printf '%s\n' '# Imagem' '' '![x](/etc/passwd){#fig:a}' '' 'Ver @fig:a.' >"$P/sections/introducao.md"
r "an image outside figures/ is refused" "$THESIS" lint sample introducao

# --- slop
cat >"$P/sections/introducao.md" <<'EOF'
No cenário atual, a previsão de ondas desempenha um papel fundamental em diversos setores da sociedade. Vale ressaltar que os modelos numéricos robustos oferecem um panorama abrangente e holístico do oceano. Além disso, é importante destacar que a computação em GPU se tornou um verdadeiro paradigma de desempenho, de precisão e de eficiência. Dessa forma, os pesquisadores buscam alavancar essa tecnologia revolucionária. Em suma, a previsão de ondas é essencial.

Além disso, ao longo dos anos, os modelos espectrais evoluíram de forma significativa e hoje abrem caminho para um leque de aplicações. Nesse sentido, cabe salientar que o WAVEWATCH III é uma ferramenta robusta, flexível e poderosa. Dessa forma, o presente trabalho propõe uma abordagem inovadora, abrangente e eficiente. Portanto, é crucial compreender esse contexto.
EOF
r "slop fails a stock-phrase paragraph" "$THESIS" slop sample introducao
cat >"$P/sections/introducao.md" <<'EOF'
Uma previsão de ondas só serve se chegar antes do mar. O WAVEWATCH III resolve o balanço de energia das ondas em cada ponto de uma grade, e repete o trabalho a cada passo de tempo. Em máquinas com CPU, o custo cresce com a grade e com o número de dias previstos.

As placas gráficas fazem o mesmo cálculo em milhares de pontos ao mesmo tempo. Quem leva o código para elas muda a ordem das contas, e uma soma feita em outra ordem pode mudar o último bit. Por isso a meta é dura: a saída em GPU deve ser igual, bit a bit, à do código em Fortran.

O trabalho porta uma parcela do modelo. A parcela foi escolhida pelo tempo que ocupa no perfil do código. A comparação lê os dois resultados como inteiros de 32 bits e conta os que diferem.
EOF
t "slop passes a plain paragraph" "$THESIS" slop sample introducao
t "slop says it is no detector" sh -c '"$0" slop sample introducao | grep -q "not a detector"' "$THESIS"

# --- cite-check: an unverified key is refused, a verified one passes
cat >"$P/sections/introducao.md" <<'EOF'
O modelo foi descrito por um grupo de teste [@exemplo2026a]. O texto seguinte repete a afirmação com outras palavras, para o teste.
EOF
cat >"$P/refs.bib" <<'EOF'
@article{exemplo2026a,
  author = {Ficticio, Autor},
  title = {Um artigo fictício de teste},
  journal = {Revista de Teste},
  year = {2020},
  volume = {1},
  doi = {10.9999/teste.2020.1}
}
EOF
cat >"$P/REFERENCES.md" <<'EOF'
| Key | Status | Checked against | Note |
|---|---|---|---|
| exemplo2026a | unverified | not fetched | FAKE |
EOF
r "cite-check refuses an unverified key" "$THESIS" cite-check sample introducao
t "the refusal says unverified" sh -c '"$0" cite-check sample introducao | grep -q "unverified"' "$THESIS"
sed -i 's/| unverified |/| verified |/' "$P/REFERENCES.md"
r "cite-check refuses a verified key with no capture file" "$THESIS" cite-check sample introducao
printf 'URL: https://example.invalid/x\nRetrieved: 2026-11-05\nDOI check: none (fictitious)\n\n> "texto fictício" (p. 1)\n' >"$P/sources/exemplo2026a.md"
t "cite-check passes a verified key with its capture" "$THESIS" cite-check sample introducao
printf 'O modelo foi descrito [@naoexiste2020]. Segue um texto de teste.\n' >"$P/sections/introducao.md"
r "cite-check refuses a key that is not in refs.bib" "$THESIS" cite-check sample introducao
printf 'O modelo foi descrito (Silva, 2020) e [3] outra coisa.\n' >"$P/sections/introducao.md"
r "cite-check refuses a numbered citation" "$THESIS" cite-check sample introducao

# --- a missing template file fails clearly
cp -rL "$SHARE_SRC" "$ROOT/share"
chmod -R u+w "$ROOT/share"
printf '%s\n' 'Texto simples para a prévia do teste.' >"$P/sections/introducao.md"
if [ -x "$WRAPPED" ]; then
  rm -f "$ROOT/share/templates/forecast-energy-demand/overlay/preamble.tex"
  r "a missing overlay file fails" env PATH="$TOOLPATH" THESIS_SHARE="$ROOT/share" "$WRAPPED" build-section sample introducao
  t "the failure names the file" sh -c 'env PATH="$TOOLPATH" THESIS_SHARE="$1" "$0" build-section sample introducao 2>&1 | grep -q "preamble.tex"' "$WRAPPED" "$ROOT/share"
  # a hung TeX run is stopped by the time limit
  cp "$SHARE_SRC/templates/forecast-energy-demand/overlay/preamble.tex" "$ROOT/share/templates/forecast-energy-demand/overlay/preamble.tex"
  chmod u+w "$ROOT/share/templates/forecast-energy-demand/overlay/preamble.tex"
  printf '\\def\\thesisloop{\\thesisloop}\\thesisloop\n' >>"$ROOT/share/templates/forecast-energy-demand/overlay/preamble.tex"
  START=$(date +%s)
  r "a hung TeX run fails" env PATH="$TOOLPATH" THESIS_SHARE="$ROOT/share" THESIS_TEX_TIMEOUT=3 "$WRAPPED" build-section sample introducao
  END=$(date +%s)
  t "the hung run was stopped by the timeout, not by luck" test "$((END - START))" -lt 20
  t "the failure says the engine was stopped" sh -c 'env PATH="$TOOLPATH" THESIS_SHARE="$1" THESIS_TEX_TIMEOUT=3 "$0" build-section sample introducao 2>&1 | grep -q "stopped"' "$WRAPPED" "$ROOT/share"
fi

# --- assemble, publish, edit after accept
printf '%s\n' 'Texto simples.' >"$P/sections/introducao.md"
: >"$P/refs.bib"
printf "%s\n" "| Key | Status | Checked against | Note |" "|---|---|---|---|" >"$P/REFERENCES.md"
t "assemble builds the PDF" "$THESIS" assemble sample
t "the PDF exists" test -s "$P/build/thesis.pdf"
t "pdf-qa passed" sh -c 'test "$(jq -r .pass "$0/build/qa.json")" = true' "$P"
t "publish copies to the outbox" "$THESIS" publish sample
r "publish refuses to overwrite another run" "$THESIS" publish sample
t "publish --replace overwrites" "$THESIS" publish sample --replace
t "the outbox has the PDF, qa.json and REFERENCES.md" sh -c 'test -s "$0/sample/thesis.pdf" -a -s "$0/sample/qa.json" -a -s "$0/sample/REFERENCES.md"' "$THESIS_OUTBOX"
printf '\nUma frase nova depois do aceite.\n' >>"$P/sections/resumo.md"
t "an edit after accept shows as changed" sh -c '"$0" sections sample | grep -q "resumo .* changed"' "$THESIS"
r "assemble refuses a section edited after its accept" "$THESIS" assemble sample
r "publish refuses a section edited after its accept" "$THESIS" publish sample --replace

echo
echo "$N checks, $FAILED failed"
[ "$FAILED" -eq 0 ]
