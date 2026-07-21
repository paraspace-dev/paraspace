local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Generic fenced block; default language is "typescript"
  s("```", fmt([[
```{}
{}
```]], { i(1, "typescript"), i(2) })),

  s("```ts", fmt([[
```typescript
{}
```]], { i(1) })),

  s("ts", fmt([[
```typescript
{}
```]], { i(1) })),
}
