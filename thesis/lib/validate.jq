# validate.jq: the problems of a thesis.json, one string each.
#   jq -r --slurpfile prof profile.json --argjson final true -f validate.jq thesis.json
# final: the meta data must be filled (no "A PREENCHER"). The sections are always checked.

def todo: . == "A PREENCHER" or . == "" or . == null;
def str: type == "string";
. as $t
| $prof[0] as $p
| ($p.courses | map(.name)) as $courses
| [
    (if ($t.title | str | not) or ($t.title | todo) then "title is not filled" else empty end),
    (if ($t.author | str | not) or ($t.author | todo) then "author is not filled" else empty end),
    (if ($t.advisor | str | not) or ($t.advisor | todo) then "advisor is not filled" else empty end),
    (if ($t.title_en | str | not) or ($t.title_en | todo) then "title_en is not filled" else empty end),
    (if ($t.author_ref | str | not) or ($t.author_ref | todo) then "author_ref is not filled (SURNAME, Given names)" else empty end)
  ] as $unfilled
| [
    (if ($courses | index($t.course)) == null then "course must be one of the Poli courses (norma 2026, 5.1), as \"Engenharia X\": \($courses | join("; "))" else empty end),
    (if ($t.month | type) != "number" or $t.month < 1 or $t.month > 12 or ($t.month | floor) != $t.month then "month must be 1 to 12" else empty end),
    (if ($t.year | type) != "number" or $t.year < 2000 or $t.year > 2100 then "year must be a four-digit number" else empty end),
    (if $t.language != "pt-BR" then "language must be pt-BR (Res. 05/2012; norma 2026, 6.1)" else empty end),
    (if $t.citation_style != "author-date" then "citation_style must be author-date: one system for the whole work" else empty end),
    (if ($t.examiners | type) != "array" or ($t.examiners | map(type == "string") | all | not) then "examiners must be a list of strings" else empty end),
    (if ($t.sections | type) != "array" or ($t.sections | length) == 0 then "sections must be a non-empty list" else empty end)
  ] as $meta
| ($t.sections // []) as $s
| [
    ($s | group_by(.id)[] | select(length > 1) | "the section id \(.[0].id) is in the list twice"),
    ($s | group_by(.order)[] | select(length > 1) | "the order \(.[0].order) is used by \(map(.id) | join(", "))"),
    ($s[] | select((.id | str | not) or (.id | test("^[A-Za-z0-9_-]+$") | not)) | "the section id \(.id | tostring) is not letters, digits, - and _"),
    ($s[] | select((.kind | IN("pretextual", "textual", "postextual")) | not) | "\(.id): kind must be pretextual, textual or postextual"),
    ($s[] | select((.role | IN("resumo", "abstract", "agradecimentos", "dedicatoria", "chapter", "appendix")) | not) | "\(.id): role must be resumo, abstract, agradecimentos, dedicatoria, chapter or appendix"),
    ($s[] | select(.role == "chapter" and .kind != "textual") | "\(.id): a chapter is textual"),
    ($s[] | select(.role == "appendix" and .kind != "postextual") | "\(.id): an appendix is postextual"),
    ($s[] | select(.role != "chapter" and .role != "appendix" and .kind != "pretextual") | "\(.id): \(.role) is pretextual"),
    ($s[] | select((.title | str | not) or (.title | todo)) | "\(.id): title is not filled"),
    ($s[] | select((.brief | str | not) or (.brief | todo)) | "\(.id): brief is not filled"),
    ($s[] | select((.brief | type) == "string" and (.brief | test("sections/|@cap:"))) | "\(.id): a brief may not point at the text of another section (sections are independent)"),
    ($s[] | select((.order | type) != "number") | "\(.id): order must be a number"),
    ($s[] | select((.target_words | type) != "number" or .target_words < 0) | "\(.id): target_words must be a number"),
    ($s[] | select((.status | IN("todo", "omit")) | not) | "\(.id): status in thesis.json is todo or omit (progress is in state/)"),
    ($s[] | . as $x | select(($p.cite.score_targets | has($x.cite_class // "medium")) | not) | "\(.id): cite_class must be one of \($p.cite.score_targets | keys | join(", "))"),
    ($s[] | select((.sources // [] | type) != "array" or ((.sources // []) | map(type == "string" and test("^[A-Za-z0-9_:.-]+$")) | all | not)) | "\(.id): sources must be a list of keys"),
    ($s[] | select((.role == "resumo" or .role == "abstract") and ((.keywords // []) | type) != "array") | "\(.id): keywords must be a list")
  ] as $secs
| ($meta + $secs + (if $final then $unfilled else [] end))[]
