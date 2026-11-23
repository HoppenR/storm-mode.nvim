---@diagnostic disable: undefined-global, undefined-field
-- setup() options
local Config = require('storm-mode.config')

describe('setup()', function()
    local before

    setup(function() before = { compiler = Config.compiler, root = Config.root, include = Config.include } end)

    teardown(function() require('storm-mode').setup(before) end)

    it('changes only the given options when called again (e.g. from a project .nvim.lua)', function()
        require('storm-mode').setup({ compiler = '/opt/storm/storm', root = '/opt/storm/root/' })
        require('storm-mode').setup({ include = { { path = '/project', package = 'project' } } })
        assert.are.equal('/opt/storm/storm', Config.compiler)
        assert.are.equal('/opt/storm/root/', Config.root)
        assert.are.same({ { path = '/project', package = 'project' } }, Config.include)
    end)

    it('replaces the include list instead of merging it', function()
        require('storm-mode').setup({ include = { { path = '/a', package = 'a' }, { path = '/b', package = 'b' } } })
        require('storm-mode').setup({ include = { { path = '/c', package = 'c' } } })
        assert.are.same({ { path = '/c', package = 'c' } }, Config.include)
        require('storm-mode').setup({ include = {} })
        assert.are.same({}, Config.include)
    end)
end)
