local M = {}

local tests = {
    runtime = "Tilua.test.production.runtime",
    health = "Tilua.test.production.health",
    metrics = "Tilua.test.production.metrics",
    exception = "Tilua.test.production.exception",
    lifecycle = "Tilua.test.production.lifecycle"
}

function M.run(scope)
    if scope ~= "production" then
        return false
    end

    local passed = true

    print("Tilua Production Test")

    for name, module in pairs(tests) do
        local ok, test = pcall(require, module)
        local result = false

        if ok and test.run then
            result = test.run()
        end

        if result then
            print("[PASS] " .. name)
        else
            print("[FAIL] " .. name)
            passed = false
        end
    end

    if passed then
        print("Production Test Passed")
    else
        print("Production Test Failed")
    end

    return passed
end

return M
