local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local rep = require("luasnip.extras").rep
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- New functional component. Shares the same $1 for the component name and
  -- its props interface — rep() mirrors node 1 into the second placeholder.
  s("fc", fmt([[
export interface {}Props {{
	{}
}}

export function {}(props: {}Props) {{
	{}
}}
]], { i(1, "Boink"), i(2), rep(1), rep(1), i(3) })),
}
