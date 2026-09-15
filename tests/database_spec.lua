describe("Tilua 2.0 database architecture", function()
    local Connection = require("Tilua.database.connection")
    local Transaction = require("Tilua.database.transaction")

    it("creates a request-scoped connection", function()
        local driver = function() return {} end
        local manager = {
            config = { default = "mock", mock = { driver = "mock" } },
            logger = nil,
            driver = function() return driver end,
        }
        local ctx = {}
        local a = Connection.new(manager, ctx, "mock")
        local b = Connection.new(manager, ctx, "mock")
        assert.is_not_equal(a, b)
        assert.are.equal(ctx, a.ctx)
    end)

    it("rolls back when transaction callback fails", function()
        local rolled_back = false
        local connection = {
            begin = function() return true end,
            commit = function() error("must not commit") end,
            rollback = function() rolled_back = true return true end,
        }
        local tx = Transaction.new(connection)
        local result = tx:run(function()
            error("boom")
        end)
        assert.is_nil(result)
        assert.is_true(rolled_back)
    end)
end)
