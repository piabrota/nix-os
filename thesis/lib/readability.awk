# readability.awk: the numbers of the human-readable gate (pt-BR). Input: the rows of prose.awk.
#
#   awk -v params=FILE -v passive_aux=FILE -v irregular=FILE -v adjlike=FILE -v anglicisms=FILE \
#       -v glossary=FILE -v groups=FILE -f readability.awk prose.tsv
#
# Prints `KEY value` lines (METRIC, WORST, PASSIVE, ANGLICISM, MIXED) for readability.sh to format.
# What is counted, and how rough it is:
#   - sentences: rows of kind p, l and q; words: tokens with a letter or digit, marks excluded.
#   - passive: a form of ser (profile lists.ser_forms), then within three tokens a participle
#     (-ado -ada -ados -adas -ido -ida -idos -idas, or an irregular one of the profile), and not an
#     adjective-like participle of the profile. The passive with -se (apassivadora) is NOT counted:
#     it cannot be told from a reflexive by rule. Adjectives that look like participles are an error
#     the other way; both are guesses.
#   - Flesch-style index for Portuguese: 248.835 - 1.015 * (words/sentences) - 84.6 * (syllables/word),
#     the constants of Martins et al. (1996), from memory. The syllable counter groups vowels and
#     splits two strong vowels (a e o) and an accented i or u: it is approximate.

function load_params(f,    line, a) {
  while ((getline line < f) > 0) {
    split(line, a, "\t")
    P[a[1]] = a[2] + 0
  }
  close(f)
}
function load_set(f, set,    line) {
  while ((getline line < f) > 0) if (line != "") set[tolower(line)] = 1
  close(f)
}
function load_lines(f, arr,    line, n) {
  n = 0
  while ((getline line < f) > 0) if (line != "") arr[++n] = line
  close(f)
  return n
}
function isvowel(c) { return c ~ /^[aeiouáéíóúâêôãõàüAEIOUÁÉÍÓÚÂÊÔÃÕÀÜ]$/ }
function strong(c) { return c ~ /^[aeoáéóâêôãõAEOÁÉÓÂÊÔÃÕ]$/ }
function syllables(w,    n, i, m, ch, c, prev, pc) {
  n = 0
  prev = 0
  pc = ""
  m = split(tolower(w), ch, "")
  for (i = 1; i <= m; i++) {
    c = ch[i]
    if (isvowel(c)) {
      if (!prev) n++
      else if ((strong(pc) && strong(c)) || c == "í" || c == "ú") n++
      prev = 1
    } else prev = 0
    pc = c
  }
  return n < 1 ? 1 : n
}
function strip(t) {
  gsub(/^[^[:alnum:]§]+|[^[:alnum:]§]+$/, "", t)
  return tolower(t)
}
function is_participle(t) {
  if (t == "sido" || t == "ido") return 0
  if (t in ADJ) return 0
  if (t in IRR) return 1
  return length(t) >= 5 && t ~ /(ado|ada|ados|adas|ido|ida|idos|idas)$/
}
function is_passive(text,    n, tk, i, j, t) {
  n = split(text, tk, " ")
  for (i = 1; i <= n; i++) {
    if (!(strip(tk[i]) in SER)) continue
    for (j = i + 1; j <= i + 3 && j <= n; j++) {
      t = strip(tk[j])
      if (is_participle(t)) return 1
    }
  }
  return 0
}
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
function median(arr, n,    i, j, t, a2) {
  for (i = 1; i <= n; i++) a2[i] = arr[i]
  for (i = 2; i <= n; i++) { t = a2[i]; for (j = i - 1; j >= 1 && a2[j] > t; j--) a2[j + 1] = a2[j]; a2[j + 1] = t }
  if (n == 0) return 0
  return (n % 2) ? a2[(n + 1) / 2] : (a2[n / 2] + a2[n / 2 + 1]) / 2
}

BEGIN {
  FS = "\t"
  load_params(params)
  load_set(passive_aux, SER)
  load_set(irregular, IRR)
  load_set(adjlike, ADJ)
  NANG = load_lines(anglicisms, ANG)
  load_set(glossary, GLOSS)
  NGRP = load_lines(groups, GRP)
  NS = 0
  NPARA = 0
}

{
  kind = $1
  if (kind != "p" && kind != "l" && kind != "q") next
  NS++
  SPARA[NS] = $2
  SLINE[NS] = $3
  SW[NS] = $4
  STEXT[NS] = $5
  SKIND[NS] = kind
  words += $4
  PCOUNT[kind ":" $2]++
  PWORDS[kind ":" $2] += $4
  if (kind == "p") PKEY[$2] = 1
  nsyl = 0
  m = split($5, tk, " ")
  for (i = 1; i <= m; i++) {
    t = tk[i]
    if (t ~ /^§[A-Z]§$/ || t !~ /[[:alnum:]]/) continue
    gsub(/[^[:alpha:]]/, "", t)
    if (t != "") nsyl += syllables(t)
  }
  syl += nsyl
  LOWER[NS] = " " tolower($5) " "
}

END {
  printf "METRIC sentences %d\n", NS
  printf "METRIC words %d\n", words
  if (NS < P["min_sentences"]) {
    printf "METRIC enough 0\n"
    exit 0
  }
  printf "METRIC enough 1\n"
  mean = words / NS
  for (i = 1; i <= NS; i++) { L[i] = SW[i]; if (SW[i] > P["sentence_long_words"]) longn++ }
  med = median(L, NS)
  printf "METRIC sentence_mean %.1f\n", mean
  printf "METRIC sentence_median %.1f\n", med
  printf "METRIC sentence_long %d\n", longn
  printf "METRIC sentence_long_share %.3f\n", longn / NS

  # Paragraphs (kind p only).
  np = 0; one = 0; maxpw = 0; sumpw = 0
  for (k in PKEY) {
    np++
    c = PCOUNT["p:" k]; w = PWORDS["p:" k]
    if (c == 1) one++
    if (w > maxpw) maxpw = w
    sumpw += w
    if (w > P["paragraph_words_max"]) bigpara++
  }
  printf "METRIC paragraphs %d\n", np
  if (np > 0) {
    printf "METRIC paragraph_mean %.1f\n", sumpw / np
    printf "METRIC paragraph_max %d\n", maxpw
    printf "METRIC paragraph_over %d\n", bigpara
    printf "METRIC one_sentence_paragraphs %d\n", one
    printf "METRIC one_sentence_share %.3f\n", one / np
  }

  # Passive voice.
  for (i = 1; i <= NS; i++) if (is_passive(STEXT[i])) { pas++; PAS[++npas] = i }
  printf "METRIC passive %d\n", pas
  printf "METRIC passive_share %.3f\n", pas / NS
  for (i = 1; i <= npas && i <= 5; i++) printf "PASSIVE %d\t%s\n", SLINE[PAS[i]], STEXT[PAS[i]]

  # Flesch-style index for Portuguese (Martins et al. 1996; constants from memory).
  flesch = 248.835 - 1.015 * (words / NS) - 84.6 * (syl / (words > 0 ? words : 1))
  printf "METRIC flesch_pt %.1f\n", flesch
  printf "METRIC syllables_per_word %.2f\n", syl / (words > 0 ? words : 1)

  # Worst sentences: the K longest.
  for (r = 1; r <= P["worst_sentences"]; r++) {
    best = 0; bw = -1
    for (i = 1; i <= NS; i++) if (!(i in USED) && SW[i] > bw) { bw = SW[i]; best = i }
    if (best == 0) break
    USED[best] = 1
    printf "WORST %d\t%d\t%s\n", SLINE[best], SW[best], STEXT[best]
  }

  # Anglicisms not in the glossary.
  for (a = 1; a <= NANG; a++) {
    term = tolower(ANG[a])
    if (term in GLOSS) continue
    for (i = 1; i <= NS; i++) {
      h = wordhit(LOWER[i], term)
      if (h > 0) { printf "ANGLICISM %s\t%d\t%d\n", ANG[a], SLINE[i], h; ANGSEEN[term] = 1 }
    }
  }
  nang = 0
  for (t in ANGSEEN) nang++
  printf "METRIC anglicisms_distinct %d\n", nang

  # Mixed terms: more than one term of a group in the section.
  nmixed = 0
  for (g = 1; g <= NGRP; g++) {
    nt = split(GRP[g], terms, "\t")
    used = 0
    listing = ""
    for (t = 1; t <= nt; t++) {
      nv = split(terms[t], vars, "|")
      hit = 0
      for (v = 1; v <= nv; v++) {
        vv = tolower(vars[v])
        if (vv in GLOSS) continue
        for (i = 1; i <= NS && !hit; i++) if (wordhit(LOWER[i], vv) > 0) hit = 1
      }
      if (hit) { used++; listing = listing (listing == "" ? "" : ", ") vars[1] }
    }
    if (used > 1) { nmixed++; printf "MIXED %s\n", listing }
  }
  printf "METRIC mixed_groups %d\n", nmixed
}
