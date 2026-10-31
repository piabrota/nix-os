# Checks .devin/wiki.json against DeepWiki's rules (docs.devin.ai, "DeepWiki"): both keys present,
# at least one and at most 30 pages, unique non-empty titles, a title and a purpose on every page,
# parents that are pages, at most 100 notes in all and 10,000 characters a note. Prints what is
# wrong and fails, or prints nothing.
#   jq -r -f scripts/deepwiki-check.jq .devin/wiki.json
. as $w
| ([$w.pages[]?.title]) as $titles
| ([($w.repo_notes // [])[], ($w.pages // [])[].page_notes[]?]) as $notes
| [
    (if ($w | has("repo_notes") | not) then "repo_notes is missing (use [] for none)" else empty end),
    (if ($w | has("pages") | not) or ($w.pages | length) == 0 then "pages must list at least one page" else empty end),
    (if ($w.pages | length) > 30 then "\($w.pages | length) pages: at most 30" else empty end),
    ($w.pages[]? | select((.title // "") == "" or (.purpose // "") == "") | "a page needs a title and a purpose: \(.)"),
    ($titles | group_by(.)[] | select(length > 1) | "duplicate page title: \(.[0])"),
    ($w.pages[]? | select(.parent and (.parent as $p | $titles | index($p) | not)) | "page \(.title): parent \(.parent) is not a page"),
    (if ($notes | length) > 100 then "\($notes | length) notes: at most 100" else empty end),
    ($notes[] | select((.content | length) > 10000) | "a note has \(.content | length) characters: at most 10000")
  ]
| if length == 0 then empty else (join("\n") + "\n" | halt_error(1)) end
