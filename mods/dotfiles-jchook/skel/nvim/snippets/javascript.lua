local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  s("it", fmt([[
it('{}', () => {{
	{}
}})]], { i(1), i(2) })),

  s("describe", fmt([[
describe('{}', () => {{
	{}
}})]], { i(1), i(2) })),
}
