---Evaluating, running and reloading code in the running Storm process
local M = {}

local Errors = require('storm-mode.errors')
local Lsp = require('storm-mode.lsp')
local Output = require('storm-mode.output')
local sym = require('storm-mode.sym').literal

local REPL_TIMEOUT_MS = 5000

---REPLs reported by the running Storm process, default first
---@type string[]?
local repls

Lsp.on_start(function() repls = nil end)

---File name of a buffer, or nil for buffers without a file
---@param bufnr integer
---@return string?
local function file_name(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' or name:match('^%a[%w+.-]*://') then return nil end
    return name
end

---Available REPLs, default first
---@return string[]
function M.repls()
    if repls == nil then
        local reply = Lsp.request_sync({ sym 'repl-available' }, REPL_TIMEOUT_MS)
        if reply ~= nil then repls = vim.tbl_filter(function(r) return type(r) == 'string' end, reply) end
    end
    return repls or {}
end

---Show the result of `repl-eval` (or `run`): (result) or (nil error)
---@param args storm-mode.sexp[]
local function on_result(args)
    local result, err = args[1], args[2]
    if type(result) == 'string' then
        Output.echo('=> ' .. result)
    elseif type(err) == 'string' then
        Output.notify(err, vim.log.levels.ERROR)
    end
end

---Evaluate an expression in the default REPL (prompts if `expr` is empty)
---@param expr? string
function M.eval(expr)
    local repl = M.repls()[1]
    if repl == nil then
        Output.notify('no REPL available in the running Storm process', vim.log.levels.ERROR)
        return
    end
    if expr == nil or expr == '' then
        vim.ui.input({ prompt = repl .. '> ' }, function(input)
            if input and input ~= '' then M.eval(input) end
        end)
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    require('storm-mode.buffer').storm_id(bufnr) -- send pending changes
    local lines = Output.stream(Output.echo)
    Lsp.capture({ sym 'repl-eval', repl, expr, file_name(bufnr) or vim.NIL }, {
        reply = true,
        on_text = function(chunk) lines:push(chunk) end,
        on_done = function(_, reply, err)
            lines:flush()
            if reply == nil then
                Output.notify('eval failed: ' .. tostring(err), vim.log.levels.ERROR)
                return
            end
            on_result(reply)
        end,
    })
end

---Storm's id for the current buffer, with all changes sent
---@return integer?
local function current_file() return require('storm-mode.buffer').storm_id(vim.api.nvim_get_current_buf()) end

---Milliseconds without output after which run output is checked for errors
local RUN_QUIET_MS = 300

---Run all public functions without parameters in the current file, or the one
---closest to the cursor. Running one function is answered with its result,
---which marks the end of its output. Running all happens asynchronously in
---Storm without a reply, so output that belongs to no other command is treated
---as output of the run, until the next run.
---@param at_cursor boolean
function M.run(at_cursor)
    local file = current_file()
    if file == nil then return end
    local message = { sym 'run', file }
    if at_cursor then
        table.insert(message, require('storm-mode.buffer').cursor_char(vim.api.nvim_get_current_buf()))
    end
    local scope = { vim.api.nvim_get_current_buf() }
    local lines = Output.stream(Output.echo)

    if at_cursor then
        Lsp.capture(message, {
            reply = true,
            on_text = function(chunk) lines:push(chunk) end,
            on_done = function(text, reply, err)
                lines:flush()
                if err then return end
                if reply then on_result(reply) end
                Errors.from_compile_output(text, scope)
            end,
        })
        return
    end

    -- Start first: starting Storm resets the output stream
    Lsp.start()
    local output = ''
    local generation = 0
    Lsp.set_output_stream(function(chunk)
        lines:push(chunk)
        output = output .. chunk
        -- Check for errors once the output pauses
        generation = generation + 1
        local current = generation
        vim.defer_fn(function()
            if current ~= generation then return end
            lines:flush()
            Errors.from_compile_output(output, scope)
        end, RUN_QUIET_MS)
    end)
    Lsp.send(message)
end

---Write modified buffers (with a file) matching `pred`
---@param pred fun(bufnr: integer): boolean
function M.write_buffers(pred)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.api.nvim_buf_is_loaded(bufnr)
            and vim.bo[bufnr].modified
            and vim.bo[bufnr].buftype == ''
            and file_name(bufnr)
            and pred(bufnr)
        then
            vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent update') end)
        end
    end
end

---Send a reload request and show its outcome
---@param targets (integer|string)[] file ids, files or directories
---@param scope (integer|string)[] files whose compile errors are replaced
local function reload(targets, scope)
    Lsp.capture({ sym 'reload', unpack(targets) }, {
        on_done = function(text, _, err)
            if err then return end
            Output.notify(text, Output.level_of(text))
            Errors.from_compile_output(text, scope)
        end,
    })
end

---Reload the current (storm-mode) buffer in Storm, with its current content
function M.reload_buffer()
    local file = current_file()
    if file == nil then return end
    reload({ file }, { vim.api.nvim_get_current_buf() })
end

---Reload the package (directory) of the current buffer; Storm reads it from
---disk, so modified buffers in it are written first
function M.reload_package()
    local name = file_name(vim.api.nvim_get_current_buf())
    if name == nil then
        Output.notify('the buffer has no file', vim.log.levels.ERROR)
        return
    end
    local dir = vim.fn.fnamemodify(name, ':p:h')
    M.write_buffers(function(b) return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':p:h') == dir end)
    local files = vim.tbl_filter(
        function(path) return vim.fn.isdirectory(path) == 0 end,
        vim.fn.glob(dir .. '/*', false, true)
    )
    reload({ dir .. '/' }, files)
end

---Reload files: storm-mode buffers with their content, others from disk (written
---first if modified)
---@param files string[] file names (expanded like |expand()|, e.g. `%`)
function M.reload_files(files)
    local Buffer = require('storm-mode.buffer')
    local targets, scope = {}, {}
    for _, file in ipairs(files) do
        local path = vim.fn.fnamemodify(vim.fn.expand(file), ':p')
        local bufnr = vim.fn.bufnr(path)
        local id = bufnr ~= -1 and Buffer.storm_id(bufnr) or nil
        if id then
            table.insert(targets, id)
            table.insert(scope, bufnr)
        else
            if bufnr ~= -1 then M.write_buffers(function(b) return b == bufnr end) end
            table.insert(targets, path)
            table.insert(scope, path)
        end
    end
    reload(targets, scope)
end

return M
