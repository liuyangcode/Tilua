local Runner = {}

local suites = {
    { name = "context", path = "tests.unit.context_test" },
    { name = "metrics", path = "tests.unit.metrics_test" },
    { name = "logger", path = "tests.unit.logger_test" },
    { name = "health_api", path = "tests.integration.health_test" },
    { name = "metrics_api", path = "tests.integration.metrics_test" },
    { name = "boot", path = "tests.lifecycle.boot_test" },
    { name = "cleanup", path = "tests.lifecycle.cleanup_test" },
}

local function execute_suite(item)
    local ok, suite = pcall(require, item.path)
    if not ok then
        return false, suite
    end

    if type(suite.run) == "function" then
        local result, err = pcall(suite.run)
        if not result then
            return false, err
        end
    end

    return true
end

function Runner.run()
    local passed = 0
    local failed = 0

    print("Tilua Test")
    print("")

    for _, suite in ipairs(suites) do
        local ok, err = execute_suite(suite)

        if ok then
            passed = passed + 1
            print("[PASS] " .. suite.name)
        else
            failed = failed + 1
            print("[FAIL] " .. suite.name)
            print("       " .. tostring(err))
        end
    end

    print("")
    print("Passed: " .. passed)
    print("Failed: " .. failed)

    if failed == 0 then
        print("Result: PASS")
        return 0
    end

    print("Result: FAIL")
    return 1
end

return Runner
