---
name: easy-translate
description: "Make an easy version or a controlled translation of a source document: easy pt-BR, Easy Japanese or controlled Simplified Chinese. Use for a versão fácil, a translated README or site string, or a stale translation."
---

> From [h0ffmann/skills](https://github.com/h0ffmann/skills/blob/bcccf4950e100ed0ae25291143f963ee09390a08/skills/writing/easy-translate/SKILL.md), for `site/locale/`. A figure here uses archify, never Mermaid.

# easy-translate

A translation is always made from its source. The source is the truth. Never edit a translation
on its own, and never add a fact that the source does not state.

## Common rules

1. Read the full source and the current translation, if one exists.
2. Find what changed in the source (`git diff`). Change the same sections of the translation.
3. Keep the same sections in the same order, so a reader can go between the two files.
4. Do not translate code, commands, file names, URLs, DOIs, licence names, project names or
   names of people. Translate only the comments in a code block.
5. Keep a quotation in its language. Put the translation after it.
6. Shorten when necessary, but never invent. A long table can become one sentence that names
   the section of the source.
7. Mark each translation that a native reader did not check. Only the owner or a native reader
   removes the mark.
8. Give the owner a literal back-translation into English for each new or changed part.

## The header

Each translation starts with a header block in its own language. It says:

- **the source wins** when the two texts do not agree.
- **made from**: the source file and its date, or its `git hash-object` value.
- **for whom**: the reader.
- **left out**: what was shortened, and where it is in the source.
- **written by**: the agent and the skill, and who reviewed it, or "not reviewed".

## Easy pt-BR ("versão fácil")

- File: `<name>.easy.pt-BR.md` next to the source.
- Sentences of 20 words or fewer, one idea each, active voice, present tense, "você".
- Common words: "arquivo", not "artefato". Explain a hard word once: "DOI (um identificador
  que não muda)".
- Keep the case of the source. A lower-case README gives a lower-case easy version.
- For text that a person reads on a site, also apply `ptbr-writer` at the `leve` level.

## Easy Japanese (やさしい日本語)

- File: `<page>-ja.md`. Translate from the English page only.
- One idea in each sentence, 40 characters or fewer. Use the です/ます form.
- Use common words. Give the reading of a technical word at its first use: `浸水（しんすい）`.
- Put spaces between phrases (分かち書き). Use Arabic numerals and an explicit unit.
- Review banner: `> ⚠ この ページは 英語の ページから 翻訳（ほんやく）しました。日本語を 話す 人が まだ チェックしていません。`

## Controlled Simplified Chinese

- File: `<page>-zh.md`. Translate from the English page only.
- One action in each sentence: 40 characters or fewer, 30 for an instruction.
- Explicit subject, active voice. Do not use `被` without an agent.
- Full verbs: `测试`, not `进行测试`. Two `的` or fewer in one noun phrase.
- No 成语, slang or metaphor. Full-width punctuation. A space between Chinese and Latin text.
- Fixed modality: `必须` is an obligation, `应` a recommendation, `可以` a capability.
- Review banner: `> ⚠ 本页由英文页面翻译。母语者尚未审校。`

## Site strings

When a site keeps its strings in a table (`translations/pt-BR.tsv` or an i18n JSON file):

1. The English string is the key. Do not change it to make the translation easier.
2. Use the owner's own words first, if a page of the owner already says it.
3. Say it as a Brazilian developer says it to a friend. Keep "commit", "build", "fork" and
   "pull request" in English.
4. Record for each row: source, translation, how (`plain`, `adapted` or `kept`), a note, the
   status (`draft`) and the author. Only the owner sets `reviewed`.
5. Keep ICU placeholders intact. Read each plural and select branch.

## Output

1. The path of each file that you wrote.
2. The back-translation of each new or changed part.
3. The words that you were not sure about.
