local K = require("modules.rebind")

hl.bind(K("Print"), hl.dsp.exec_cmd("ryoku-cmd-ryoshot"))
hl.bind(K("SHIFT + Print"), hl.dsp.exec_cmd("env RYOSHOT_MODE=monitor ryoku-cmd-ryoshot"))
