# site/design

The designs of the site, as OpenPencil `.fig` files. `.mcp.json` limits the `open-pencil` MCP
server to this folder (`OPENPENCIL_MCP_ROOT`), so an agent reads and writes designs here and
nowhere else in the repository.

A design here is a draft. The page itself is the Gleam code in `../src`: once a design is agreed,
change `app.gleam` and `../static/style.css` to match it, and run `just site-test`. Nothing in this
folder is built or deployed.
