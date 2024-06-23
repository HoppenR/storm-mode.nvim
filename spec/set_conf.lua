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
