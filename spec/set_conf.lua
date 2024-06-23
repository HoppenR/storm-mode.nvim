-- Helper script for setting configuration options before running tests both
-- locally, and when the Storm files are not in the default location.

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
