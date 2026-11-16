-- thesis.lua: the one pandoc filter of the thesis toolkit. It runs BEFORE --citeproc.
--
--  1. Cross-references. pandoc-crossref is not used (its closure is 5.5 GiB). Labels: a figure
--     `![caption](figures/x.pdf){#fig:name}`, a table caption `: caption {#tbl:name}`, an equation
--     `$$ ... $$ {#eq:name}`, a heading `# Title {#sec:name}`. References: `@fig:name`, `@tbl:name`,
--     `@eq:name`, `@sec:name` (labels of THIS section only) and `@cap:<section id>` (a chapter, by the
--     id in thesis.json). A label that is never cited, or a reference with no label, is a warning,
--     and the build runs with --fail-if-warnings.
--  2. Labels get the section id in them, so two sections can use the same name.
--  3. Safety. The reader runs with raw TeX and raw HTML off. Math is the one place where pandoc passes
--     the author's text to TeX unchanged, so every control sequence in math must be on the allow list
--     (profile.json, `math_macros`); `^^`, `%` and `#` in math are refused. Image paths must stay in
--     figures/. Raw blocks and inlines (there should be none) are dropped with a warning.
--
-- Inputs: metadata `section-id`, `section-ids` (comma list of every id of thesis.json); the environment
-- variable THESIS_PROFILE (path of profile.json).

local stringify = pandoc.utils.stringify
local warn = function(msg) pandoc.log.warn('thesis.lua: ' .. msg) end

local prefixes = { fig = 'Figura', tbl = 'Tabela', eq = 'Equação', sec = 'Seção', cap = 'Capítulo' }

local function read_profile()
  local path = os.getenv('THESIS_PROFILE')
  if not path then return {} end
  local f = io.open(path, 'r')
  if not f then return {} end
  local text = f:read('a')
  f:close()
  return pandoc.json.decode(text, false)
end

local profile = read_profile()
local lists = profile.lists or {}
local allowed, envs = {}, {}
for _, name in ipairs(lists.math_macros or {}) do allowed[name] = true end
for _, name in ipairs(lists.math_envs or {}) do envs[name] = true end

local section_id = ''
local section_ids = {}
local defined = {} -- label (as written by the author) -> kind
local used = {}

local function scoped(label)
  local kind, rest = label:match('^(%a+):(.+)$')
  return kind .. ':' .. section_id .. ':' .. rest
end

local function xref_parts(id)
  local kind, rest = id:match('^(%a+):(.+)$')
  if kind and prefixes[kind] then return kind, rest end
  return nil
end

local function math_ok(text)
  if text:find('^^', 1, true) then return false, '^^ is not allowed in math' end
  if text:find('#', 1, true) then return false, '# is not allowed in math' end
  for pos in text:gmatch('()%%') do
    if pos == 1 or text:sub(pos - 1, pos - 1) ~= '\\' then return false, 'an unescaped % is not allowed in math' end
  end
  for name in text:gmatch('\\(%a+)') do
    if not allowed[name] then return false, 'the macro \\' .. name .. ' is not on the math allow list' end
  end
  for name in text:gmatch('\\begin%s*{([^}]*)}') do
    if not envs[name] then return false, 'the environment ' .. name .. ' is not allowed in math' end
  end
  for name in text:gmatch('\\end%s*{([^}]*)}') do
    if not envs[name] then return false, 'the environment ' .. name .. ' is not allowed in math' end
  end
  return true
end

local function trailing_label(inlines, kind)
  -- "... text {#kind:name}" -> inlines without the label, name
  local n = #inlines
  if n == 0 then return nil end
  local last = inlines[n]
  if last.t ~= 'Str' then return nil end
  local name = last.text:match('^{#(' .. kind .. ':[%w_%-]+)}$')
  if not name then return nil end
  local cut = n - 1
  if cut >= 1 and (inlines[cut].t == 'Space' or inlines[cut].t == 'SoftBreak') then cut = cut - 1 end
  local out = pandoc.Inlines({})
  for i = 1, cut do out:insert(inlines[i]) end
  return out, name
end

local function walk_all(doc)
  local f = {}

  function f.Table(tbl)
    local long = tbl.caption.long
    if #long > 0 then
      local last = long[#long]
      if last.t == 'Plain' or last.t == 'Para' then
        local stripped, name = trailing_label(last.content, 'tbl')
        if name then
          last.content = stripped
          long[#long] = last
          tbl.caption.long = long
          defined[name] = 'tbl'
          tbl.attr = pandoc.Attr(scoped(name), tbl.attr.classes, tbl.attr.attributes)
        end
      end
    end
    return tbl
  end

  function f.Figure(fig)
    local id = fig.identifier
    if id and id:match('^fig:') then
      defined[id] = 'fig'
      fig.identifier = scoped(id)
    end
    return fig
  end

  function f.Header(h)
    local id = h.identifier
    if id and id:match('^sec:') then
      defined[id] = 'sec'
      h.identifier = scoped(id)
    end
    return h
  end

  function f.Math(m)
    local ok, why = math_ok(m.text)
    if not ok then
      warn(why .. ' (in: ' .. m.text:sub(1, 60) .. ')')
      return pandoc.Str('[matemática recusada]')
    end
    return m
  end

  function f.Image(img)
    local src = img.src
    if not src:match('^figures/[%w._/-]+$') or src:find('..', 1, true) then
      warn('image path ' .. src .. ': only figures/<name> (letters, digits, . _ / -) is allowed')
    end
    return img
  end

  function f.RawInline(r)
    warn('a raw ' .. r.format .. ' inline was dropped')
    return {}
  end

  function f.RawBlock(r)
    warn('a raw ' .. r.format .. ' block was dropped')
    return {}
  end

  function f.CodeBlock(cb)
    if cb.text:find('\\end{verbatim}', 1, true) then
      warn('a code block holds \\end{verbatim}')
      return pandoc.CodeBlock('[bloco recusado]')
    end
    return cb
  end

  return doc:walk(f)
end

-- `$$ ... $$ {#eq:name}` -> a numbered equation. The math was checked in the first pass.
local function convert_equations(doc)
  local f = {}
  function f.Para(p)
    local c = p.content
    if #c == 3 and c[1].t == 'Math' and c[1].mathtype == 'DisplayMath' and c[2].t == 'Space' and c[3].t == 'Str' then
      local name = c[3].text:match('^{#(eq:[%w_%-]+)}$')
      if name then
        defined[name] = 'eq'
        return pandoc.RawBlock('latex', '\\begin{equation}\\label{' .. scoped(name) .. '}\n' .. c[1].text .. '\n\\end{equation}')
      end
    end
    return nil
  end
  return doc:walk(f)
end

local function resolve_cites(doc)
  local f = {}
  function f.Cite(cite)
    local x, other = 0, 0
    for _, c in ipairs(cite.citations) do
      if xref_parts(c.id) then x = x + 1 else other = other + 1 end
    end
    if x == 0 then return nil end
    if other > 0 then
      warn('a citation mixes a cross-reference and a source key')
      return nil
    end
    local out = pandoc.Inlines({})
    for i, c in ipairs(cite.citations) do
      local kind, rest = xref_parts(c.id)
      local label
      if kind == 'cap' then
        if not section_ids[rest] then warn('@' .. c.id .. ': no section with the id ' .. rest .. ' in thesis.json') end
        label = 'ch:' .. rest
      else
        if not defined[c.id] then warn('@' .. c.id .. ' has no label in this section') end
        used[c.id] = true
        label = scoped(c.id)
      end
      if i > 1 then out:insert(pandoc.Str(', ')) end
      if kind == 'eq' then
        out:insert(pandoc.RawInline('latex', 'Equação~(\\ref{' .. label .. '})'))
      else
        out:insert(pandoc.RawInline('latex', prefixes[kind] .. '~\\ref{' .. label .. '}'))
      end
    end
    return out
  end
  return doc:walk(f)
end

function Pandoc(doc)
  section_id = stringify(doc.meta['section-id'] or '')
  for id in stringify(doc.meta['section-ids'] or ''):gmatch('[^,]+') do section_ids[id] = true end
  if section_id == '' then
    warn('the metadata section-id is missing')
    section_id = 'x'
  end
  doc = walk_all(doc)
  doc = convert_equations(doc)
  doc = resolve_cites(doc)
  for label, kind in pairs(defined) do
    if kind ~= 'eq' and kind ~= 'sec' and not used[label] then
      warn((prefixes[kind] or kind) .. ' ' .. label .. ' is never cited in the text')
    end
  end
  return doc
end
