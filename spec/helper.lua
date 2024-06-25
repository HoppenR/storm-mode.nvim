-- Helper script for setting non-default configuration options before running
-- the tests.
-- If defaults are preferred, there is no need to set the environment variables.

-- If needed, run the tests like this, or simply edit the file paths below.
-- ```
-- $ export STORM_COMPILER=~/projects/storm-lang/storm
-- $ export STORM_ROOT=~/projects/storm-lang/root/
-- $ busted
-- ```

require('storm-mode').setup({
    compiler = os.getenv('STORM_COMPILER'), -- default: "/usr/bin/storm"
    root = os.getenv('STORM_ROOT'),         -- default: "/usr/lib/storm/"
})

----- SHARED FUNCTIONS -----

---Helper function to match the first element of a message
---@param expected {[1]: storm-mode.sym, ['n']: integer}
---@return fun(actual: storm-mode.lsp.message): boolean
local function is_messagetype(_, expected)
    return function(actual) return expected[1] == actual[1] end
end
require('luassert'):register('matcher', 'messagetype', is_messagetype)
