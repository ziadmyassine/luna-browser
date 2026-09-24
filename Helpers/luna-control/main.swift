// `luna-control`: the stdio MCP server bundled in Luna.app. It relays to the
// running Luna over its user-only socket; see `ControlRelay` and
// docs/LUNA-CONTROL.md.

import LunaControl

ControlRelay(socketPath: ControlSocket.path()).run()
