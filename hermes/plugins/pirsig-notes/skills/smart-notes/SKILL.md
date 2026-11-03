---
name: smart-notes
description: Turn what the owner says or sends into smart notes and send them to the pirsig brain as one pull request. Use when the owner asks to note, save, index or send ideas, a quote or a source to pirsig.
---

# Smart notes into pirsig

You write the notes. The tools check the mechanical rules and open the pull request; they do not
judge the ideas. The rules are gramatico's smart-note level, at commit
`d57371af30553ad66f63537e52c1f34112e2f86b` of piabrota/gramatico (`SKILL.md`, "Smart note"). If
a rule here and that file differ, that file wins: read it with
`gh api repos/piabrota/gramatico/contents/SKILL.md?ref=d57371af30553ad66f63537e52c1f34112e2f86b --jq .content | base64 -d`.

## Steps

1. **Split.** One idea per note: one claim, one fact or one question. Five ideas are five notes.
2. **Classify.** `fleeting` is a raw idea as it came. `literature` is what one source says, with
   its link, DOI or citekey in `source`. `permanent` is a claim of the owner's, made from other
   notes: write it only when the owner states the claim. Never turn a source's claim into a
   permanent note.
3. **Write.** In the owner's language (pt-BR by default, with gramatico's rules: explicit subject,
   one proposition per sentence, `usar` and not `utilizar`, no em dashes in prose). Own words;
   quote only what must stay exact, in quotation marks, with the source. The title is the claim, as
   a full sentence. At most 500 words; most notes are 100 to 300.
4. **Status.** `unverified` until you read the source in this conversation and cite it in the
   note. Never `approved`: only the owner gives it.
5. **People.** A person who is not a public figure appears by nickname (`friend1`, `prof1`), never
   by name. No email addresses.
6. **Link.** Call `pirsig_note_search` with the note's key words. Link to an existing note (its
   `stem`) or to another note of this call (its title), always with a reason you can defend. With
   no neighbour, write `proposed_link`: the note that should exist and why; the file marks it `⚠`.
   Never invent a link to fill the rule.
7. **Tags.** Few, lowercase, with hyphens; reuse tags the brain already has. The tool adds
   `status/<status>` and `hermes`.
8. **Show, then send.** Show the owner the titles, kinds and links. Call `pirsig_notes_submit` only
   after the owner says to send, with `request` as one English sentence of what was asked.
9. **Report.** Give the pull request URL and each `⚠`. The owner merges and runs
   `psg fork import brain`; you do neither.

## Never

- Rewrite or delete a note that is already in the brain. The tool refuses it too.
- Invent a source, a quote, a number or a reference. Mark what you did not check with `⚠`.
- Send a note the owner did not see.
