#!/bin/sh
# omp-stream: reads the JSON lines of `omp -p --mode json` on stdin and prints one plain line per
# event, at once, so the output of omp reaches the conversation while omp works.
#
#   omp -p --mode json --no-title < task.md 2>&1 | omp-stream
#
# Prints: the start, each tool call and its result (the first 5 lines), each finished assistant
# text, and the end with the turns and the cost. A line that is not JSON (a stderr line) prints as
# `omp stderr: <line>`. Keys and tokens print as [redacted]. It reads stdin only: no file, no
# network. Needs jq 1.7 or later. Test: sh test-omp-stream.sh.
exec jq -nRr --unbuffered '
def redact:
  gsub("sk-ant-[A-Za-z0-9_-]+"; "[redacted]")
  | gsub("gh[pousr]_[A-Za-z0-9]+"; "[redacted]")
  | gsub("github_pat_[A-Za-z0-9_]+"; "[redacted]");
def cut($n): if length > $n then .[:$n] else . end;
def oneline: gsub("\\s+"; " ");
def cost4:
  (. * 10000 | round) as $c
  | "\($c / 10000 | floor).\(($c % 10000 | tostring) | ("0000" + .)[-4:])";
def argsum:
  if type == "object"
  then ((.command | strings) // (.path | strings) // ([.[] | strings][0]) // "")
  else "" end;

foreach inputs as $raw ({turns: 0, cost: 0, out: []};
  . as $s
  | try (
      (try ($raw | fromjson) catch null) as $e
      | if ($raw | test("\\S") | not) then .out = []
        elif ($e | type) != "object" then .out = ["omp stderr: " + ($raw | cut(300))]
        elif $e.type == "session" then .out = ["omp: start in \($e.cwd // "?")"]
        elif $e.type == "tool_execution_start" then
          ($e.toolName // "tool") as $n
          | (($e.intent | strings | oneline | select(length > 0))
             // ($e.args | argsum | oneline | select(length > 0))
             // "") as $d
          | .out = ["> \($n)" + (if $d == "" then "" else ": " + ($d | cut(200)) end)]
        elif $e.type == "tool_execution_end" then
          ($e.toolName // "tool") as $n
          | ([$e.result.details.wallTimeMs? | numbers | round][0]) as $ms
          | ([($e.result.content? // [])[]?
              | select(type == "object" and .type == "text") | .text | strings]
             | join("\n") | sub("\\s+$"; "")) as $t
          | ($t | if length == 0 then [] else split("\n") end) as $l
          | .out = (
              ["< \($n) \(if $e.isError == true then "ERROR" else "ok" end)"
               + (if $ms != null then " (\($ms) ms)" else "" end)]
              + ($l[:5] | map("    " + cut(160)))
              + (if ($l | length) > 5 then ["    ... \(($l | length) - 5) more lines"] else [] end))
        elif $e.type == "message_update"
             and $e.assistantMessageEvent.type? == "text_end" then
          .out = ["omp says: " + ($e.assistantMessageEvent.content // "" | tostring | cut(1500))]
        elif $e.type == "message_end" and $e.message.role? == "assistant" then
          .cost += (([$e.message.usage.cost.total? | numbers][0]) // 0) | .out = []
        elif $e.type == "turn_end" then .turns += 1 | .out = []
        elif $e.type == "agent_end" and ($e.isTerminal // true) then
          .out = ["omp: done, \(.turns) turns, cost $\(.cost | cost4)"]
        else .out = [] end
    ) catch ($s | .out = ["omp-stream: cannot read one event"]);
  .out[] | redact)
'
