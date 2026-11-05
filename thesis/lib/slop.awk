# slop.awk: surface patterns that models overuse, in one pt-BR section. NO external detector, no
# model. It measures patterns, not authorship: a person writes some of them, and a careful editor
# removes all of them from a model's text. The score cannot promise any detector's result. The fix
# is to rewrite from facts, with the author's own data and decisions, not to paraphrase.
#
#   awk -v params=FILE -v phrases=FILE -v transitions=FILE -v summaries=FILE -v hedges=FILE \
#       -f slop.awk prose.tsv section.md
#
# Prints `SIGNAL name value warn max points`, `SPAN name line text`, `SCORE n`, `WORDS n`.
# A signal scores weight * clamp((value - warn) / (max - warn), 0, 1); the score is the sum (0..100).

function load_params(f,    line, a) {
  while ((getline line < f) > 0) {
    split(line, a, "\t")
    P[a[1]] = a[2] + 0
  }
  close(f)
}
function load_lines(f, arr,    line, n) {
  n = 0
  while ((getline line < f) > 0) if (line != "") arr[++n] = tolower(line)
  close(f)
  return n
}
function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
function wordhit(low, term,    pos, before, after, start, found) {
  start = 1
  found = 0
  while ((pos = index(substr(low, start), term)) > 0) {
    pos = pos + start - 1
    before = (pos == 1) ? " " : substr(low, pos - 1, 1)
    after = substr(low, pos + length(term), 1)
    if (before !~ /[[:alpha:]]/ && after !~ /[[:alpha:]]/) found++
    start = pos + length(term)
  }
  return found
}
function cleanword(t) {
  gsub(/^[^[:alnum:]§]+|[^[:alnum:]§]+$/, "", t)
  return tolower(t)
}
function firstkey(text,    tk, n, w1, w2) {
  n = split(text, tk, " ")
  w1 = cleanword(tk[1])
  if (w1 ~ /^(o|a|os|as|um|uma|de|da|do|em|no|na|por|para|com|que|e|se|ao|à|nos|nas)$/) {
    w2 = cleanword(tk[2])
    return w1 " " w2
  }
  return w1
}
function stdev(arr, n, mean,    i, s) {
  s = 0
  for (i = 1; i <= n; i++) s += (arr[i] - mean) ^ 2
  return sqrt(s / n)
}
function points(name, value,    w, a, b) {
  w = P["weights." name]; a = P["warn." name]; b = P["max." name]
  if (b == a) return 0
  return w * clamp((value - a) / (b - a))
}
function emit(name, value,    pt) {
  pt = points(name, value)
  SCORE += pt
  printf "SIGNAL %s %.3f %s %s %.1f\n", name, value, P["warn." name], P["max." name], pt
}
function ngram_key(i, n,    k, s) {
  s = ""
  for (k = 0; k < n; k++) s = s (k ? " " : "") TOK[i + k]
  return s
}

BEGIN {
  FS = "\t"
  load_params(params)
  NPH = load_lines(phrases, PH)
  NTR = load_lines(transitions, TR)
  NSU = load_lines(summaries, SU)
  NHE = load_lines(hedges, HE)
  title = ENVIRON["SLOP_TITLE"]
  NS = 0
  SCORE = 0
}

# File 1: the sentences. File 2: the raw lines of the section.
FILENAME == ARGV[ARGC - 2] {
  if ($1 != "p" && $1 != "l" && $1 != "q") next
  NS++
  SPARA[NS] = $2; SLINE[NS] = $3; SW[NS] = $4; STEXT[NS] = $5; SKIND[NS] = $1
  WORDS += $4
  LOW[NS] = " " tolower($5) " "
  if ($1 == "p") { PCNT[$2]++; if (!($2 in PFIRST)) { PFIRST[$2] = NS; NPARA++; PORDER[NPARA] = $2 } PLAST[$2] = NS }
  next
}

FILENAME == ARGV[ARGC - 1] {
  raw = $0
  sub(/\r$/, "", raw)
  if (raw ~ /^[ ]{0,3}(```|~~~)/) { RFENCE = !RFENCE; next }
  if (RFENCE) next
  t = raw
  gsub(/`[^`]*`/, "", t)
  gsub(/\$[^$]*\$/, "", t)
  gsub(/\*\*\[(AUTHOR|ANALYSIS)[^]]*\]\*\*/, "", t)
  nd = 0
  s = t
  while (match(s, /—|---| – | -- /)) { nd++; DASHL[++ND] = FNR; s = substr(s, RSTART + RLENGTH) }
  if (raw ~ /^[ ]*([-*+]|[0-9]+[.)])[ ]+\*\*[^*]+\*\*/) { NB++; BOLDL[NB] = FNR; BOLDT[NB] = raw }
  next
}

END {
  printf "WORDS %d\n", WORDS
  if (WORDS < P["min_words"]) {
    printf "SCORE 0\nTOOSHORT 1\n"
    exit 0
  }
  per1000 = 1000 / WORDS

  # 1. Stock phrases.
  nh = 0
  for (i = 1; i <= NS; i++)
    for (p = 1; p <= NPH; p++) {
      h = wordhit(LOW[i], PH[p])
      if (h > 0) { nh += h; printf "SPAN phrases %d\t%s\n", SLINE[i], PH[p] }
    }
  emit("phrases", nh * per1000)

  # 2. Em dashes and spaced en dashes.
  emit("dashes", ND * per1000)
  for (i = 1; i <= ND && i <= 8; i++) printf "SPAN dashes %d\tdash\n", DASHL[i]

  # 3. Three parallel parts.
  K = P["tricolon_item_max_words"] - 1
  re = "([[:alpha:]-]+ ){0," K "}[[:alpha:]-]+, ([[:alpha:]-]+ ){0," K "}[[:alpha:]-]+,? (e|ou) ([[:alpha:]-]+ ){0," K "}[[:alpha:]-]+"
  nt = 0
  for (i = 1; i <= NS; i++)
    if (match(STEXT[i], re)) { nt++; printf "SPAN tricolon %d\t%s\n", SLINE[i], substr(STEXT[i], RSTART, RLENGTH) }
  emit("tricolon", nt / NS)

  # 4. The same opening on consecutive sentences of one paragraph.
  runs = 0
  run = 1
  for (i = 2; i <= NS + 1; i++) {
    if (i <= NS && SPARA[i] == SPARA[i - 1] && SKIND[i] == SKIND[i - 1] && firstkey(STEXT[i]) == firstkey(STEXT[i - 1]) && firstkey(STEXT[i]) != "") run++
    else {
      if (run >= P["same_opening_run"]) { runs++; printf "SPAN same_opening %d\t%d sentences begin with \"%s\"\n", SLINE[i - run], run, firstkey(STEXT[i - 1]) }
      run = 1
    }
  }
  emit("same_opening", runs)

  # 5. Low variation of sentence length (stdev / mean).
  if (NS >= P["min_sentences_for_cv"]) {
    mean = WORDS / NS
    for (i = 1; i <= NS; i++) L[i] = SW[i]
    cv = stdev(L, NS, mean) / mean
    emit("low_variation", cv)
  } else printf "SIGNAL low_variation n/a - - 0\n"

  # 6. Paragraphs of three sentences or more that end with a summary sentence.
  elig = 0; sumend = 0
  for (j = 1; j <= NPARA; j++) {
    pid = PORDER[j]
    if (PCNT[pid] < 3) continue
    elig++
    last = LOW[PLAST[pid]]
    sub(/^ [„“"(]*/, "", last)
    for (s = 1; s <= NSU; s++) if (index(last, SU[s]) == 1) { sumend++; printf "SPAN summary_endings %d\t%s\n", SLINE[PLAST[pid]], substr(STEXT[PLAST[pid]], 1, 70); break }
  }
  emit("summary_endings", elig >= 3 ? sumend / elig : 0)

  # 7. Repeated 4-grams (words only, inside a sentence).
  n = P["ngram_size"]
  for (i = 1; i <= NS; i++) {
    m = split(STEXT[i], tk, " ")
    cnt = 0
    for (k = 1; k <= m; k++) {
      w = cleanword(tk[k])
      if (w == "" || w ~ /^§/ || w ~ /[0-9]/ || w == "math" || w == "code") { cnt = 0; continue }
      TOKQ[++cnt] = w
      if (cnt >= n) {
        key = ""
        for (q = cnt - n + 1; q <= cnt; q++) key = key (key == "" ? "" : " ") TOKQ[q]
        NG[key]++
        if (!(key in NGL)) NGL[key] = SLINE[i]
      }
    }
  }
  nr = 0
  for (key in NG) if (NG[key] >= P["ngram_min_repeats"]) { nr++; printf "SPAN repeated_ngrams %d\t\"%s\" x%d\n", NGL[key], key, NG[key] }
  emit("repeated_ngrams", nr * per1000)

  # 8. Hedging per 1000 words.
  nhd = 0
  for (i = 1; i <= NS; i++) for (h = 1; h <= NHE; h++) nhd += wordhit(LOW[i], HE[h])
  emit("hedging", nhd * per1000)

  # 9. Bold lead-ins in lists.
  emit("bold_leadins", NB)
  for (i = 1; i <= NB && i <= 5; i++) printf "SPAN bold_leadins %d\t%s\n", BOLDL[i], substr(BOLDT[i], 1, 70)

  # 10. An opening that restates the heading.
  nc = split(tolower(title), TT, /[^[:alpha:]]+/)
  ncw = 0; ov = 0
  first = (NPARA > 0) ? LOW[PFIRST[PORDER[1]]] : ""
  for (i = 1; i <= nc; i++) if (length(TT[i]) >= 5) { ncw++; if (wordhit(first, TT[i]) > 0) ov++ }
  rest = (ncw >= 2) ? ov / ncw : 0
  if (first ~ /^ (este|neste|o presente|nesse|neste) (capítulo|seção|trabalho|texto)/) rest = (rest > 0.5 ? rest : 0.5) + 0.4
  if (rest > 1) rest = 1
  emit("restated_heading", rest)
  if (rest >= P["warn.restated_heading"]) printf "SPAN restated_heading %d\t%s\n", SLINE[PFIRST[PORDER[1]]], substr(STEXT[PFIRST[PORDER[1]]], 1, 80)

  # 11. Generic transitions at the start of paragraphs.
  ntr = 0
  for (j = 1; j <= NPARA; j++) {
    low = LOW[PFIRST[PORDER[j]]]
    sub(/^ [„“"(]*/, "", low)
    for (s = 1; s <= NTR; s++) if (index(low, TR[s]) == 1) { ntr++; printf "SPAN transitions %d\t%s\n", SLINE[PFIRST[PORDER[j]]], TR[s]; break }
  }
  emit("transitions", NPARA >= 4 ? ntr / NPARA : 0)

  printf "SCORE %.0f\n", SCORE
}
