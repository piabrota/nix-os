---
name: eli5
description: "Explain a topic of the current project to a reader who knows nothing about it. Draw a picture first and take each fact from the checkout. Use for /eli5 <topic> or \"explain this simply\"."
---

> From [h0ffmann/skills](https://github.com/h0ffmann/skills/blob/bcccf4950e100ed0ae25291143f963ee09390a08/skills/research/eli5/SKILL.md), for `site/locale/`. A figure here uses archify, never Mermaid.

# eli5

Explain as if the reader knows nothing about the topic. Use short sentences, one idea at a time,
and a picture before the prose.

Topic: $ARGUMENTS

## Base it on the checkout

An explanation that does not agree with the code, the corpus or the docs is worse than no
explanation. Before you write, read the files that cover the topic:

- the knowledge corpus or the notes, when the topic is a fact of the field.
- the architecture and design docs, when the topic is how the project works.
- the MIP or ADR, when the topic is why it has its shape.
- the code, for what it really does.

If the checkout and your memory do not agree, the checkout wins. If neither covers the topic,
say so. A MIP that is `Draft` or `Accepted` describes something that does not exist yet. Say
"proposed in MIP-NNNN", never the present tense.

## How to explain

1. **One sentence first.** What it is, in words that a person on the beach knows. No jargon.
2. **A picture.** A Mermaid diagram or a small ASCII sketch of the thing at work. Use the words
   of the first sentence as labels. Ten nodes or fewer.
3. **The words of the field.** Now give the correct names, one line each, tied to the picture.
4. **Why it matters here.** One or two lines that connect it to what the project does.
5. **Where to read more.** Only the files and pages that you opened. Mark each claim that you
   did not check as "not checked".

## Analogies

Use physical analogies: water, queues, kitchens, mail. Say where the analogy breaks before the
reader finds it. An analogy never replaces the real definition.

## Audience and language

The default reader is curious and has no science background. "For a developer" adds the real
types and paths. Answer in the language of the request. In pt-BR, use the words that people use,
and give the English term once in brackets.

## Safety topics are not advice

An explanation of a hazard (rip currents, stings, water quality, sea state) explains the
mechanism. It does not tell a person whether to enter the water. It gives no first aid beyond
what a sourced file states.

## Output

The default is a chat answer with the diagram inline. If the request asks for a page, write one
HTML file with large type into a folder that git ignores (`.tmp/eli5/`). Do not write other
files. Do not commit.

## Do not

- Do not invent numbers. Each number comes from a file or a fetched page, or it is marked.
- Do not paste code to explain. Ten lines are acceptable when the code is the point.
