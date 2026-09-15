--- Minimal `random` stand-in for the end-to-end test only.
--- Tilua.utils.util requires this module but never uses it (see
--- docs/ANALYSIS.md 5.1).
return {
    bytes = function(n)
        return string.rep("0", n or 1)
    end,
}
