---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Dotted pairs decode to arrays with a `tail` field, e.g. { "a", tail = "b" }
--# selene: allow(mixed_table)
local Dec = require('storm-mode.decoder')
local Enc = require('storm-mode.encoder')
local sym = require('storm-mode.sym').literal
local simple_deserial = { sym 'a', 10, sym 'a', 'b' } ---@type storm-mode.lsp.message
local simple_serial = string.char(
    0x0,
    0x0,
    0x0,
    0x0,
    0x1F,
    0x1,
    0x4,
    0x0,
    0x0,
    0x0,
    0x1,
    0x0,
    0x0,
    0x0,
    0x1,
    0x61,
    0x1,
    0x2,
    0x0,
    0x0,
    0x0,
    0xA,
    0x1,
    0x5,
    0x0,
    0x0,
    0x0,
    0x1,
    0x1,
    0x3,
    0x0,
    0x0,
    0x0,
    0x1,
    0x62,
    0x0
)
local nil_deserial = { sym 'debug', vim.NIL } ---@type storm-mode.lsp.message
local nil_serial = string.char(
    0x0,
    0x0,
    0x0,
    0x0,
    0x12,
    0x1,
    0x4,
    0x0,
    0x0,
    0x0,
    0x1,
    0x0,
    0x0,
    0x0,
    0x5,
    0x64,
    0x65,
    0x62,
    0x75,
    0x67,
    0x1,
    0x0,
    0x0
)
-- Numbers > 255 are the common case for changedtick and character positions in
-- files longer than 255 bytes. Test encode→decode roundtrip for each boundary.
local largenum_cases = {
    { 256, { 0x0, 0x0, 0x1, 0x0 } },
    { 300, { 0x0, 0x0, 0x1, 0x2C } },
    { 65535, { 0x0, 0x0, 0xFF, 0xFF } },
    { 65536, { 0x0, 0x1, 0x0, 0x0 } },
    { 0x19203828, { 0x19, 0x20, 0x38, 0x28 } },
}

describe('messaging', function()
    before_each(function()
        Enc._next_symid = 1
        require('storm-mode.sym').reset()
    end)

    it('encodes sample', function()
        local encoded = Enc.enc_message(simple_deserial)
        assert.equals(simple_serial, encoded, 'should encode correctly')
    end)

    it('encodes vim.NIL in message', function()
        local encoded = Enc.enc_message(nil_deserial)
        assert.equals(nil_serial, encoded, 'should encode nil')
    end)

    it('roundtrips numbers > 255', function()
        for _, case in ipairs(largenum_cases) do
            local n, bytes = case[1], case[2]
            local msg = { n } ---@type storm-mode.lsp.message
            local encoded = Enc.enc_message(msg)
            -- Verify the number bytes are correct
            local expected_body = string.char(0x1, 0x2, unpack(bytes)) .. string.char(0x0)
            local expected = string.char(0x0) .. Enc.enc_number(#expected_body) .. expected_body
            assert.equals(expected, encoded, 'encode mismatch for ' .. tostring(n))
            -- Verify decode roundtrip
            local decoded, rest = Dec.dec_message(encoded)
            assert.are_same(msg, decoded, 'decode mismatch for ' .. tostring(n))
            assert.equals('', rest)
        end
    end)

    it('decodes sample', function()
        local decoded, rest = Dec.dec_message(simple_serial)
        assert.are_same(simple_deserial, decoded, 'should decode correctly')
        assert.equal(rest, '', 'should consume all characters')
    end)

    it('decodes nil in message', function()
        local decoded, rest = Dec.dec_message(nil_serial)
        assert.are_same(nil_deserial, decoded, 'should decode nil')
        assert.equal(rest, '', 'should consume all characters')
    end)

    it('rejects incomplete message', function()
        local bad_message = simple_serial:sub(1, math.floor(#simple_serial / 2))
        local decoded, rest = Dec.dec_message(bad_message)
        assert.is_nil(decoded, 'should not decode incomplete message')
        assert.equal(bad_message, rest, 'should return incomplete message')
    end)

    it('returns UTF-8 and unprocessed data', function()
        local prepend_str = 'Hello, World!'
        local decoded, rest = Dec.dec_message(prepend_str .. simple_serial)
        assert.is_equal(prepend_str, decoded, 'should return UTF-8 first')
        assert.is_equal(simple_serial, rest, 'should return unprocessed data')
    end)

    it('returns trailing data', function()
        local appended_str = 'Hello, World!'
        local decoded, rest = Dec.dec_message(simple_serial .. appended_str)
        assert.are_same(simple_deserial, decoded)
        assert.is_equal(rest, appended_str)
    end)

    it('returns nil on empty data', function()
        local decoded, rest = Dec.dec_message('')
        assert.is_nil(decoded)
        assert.is_equal(rest, '')
    end)

    it('roundtrips nested lists and dotted pairs', function()
        -- Shape of a (documentation ...) reply
        local msg = {
            sym 'documentation',
            {
                {
                    'print',
                    { { 's', 'core.Str', 'core.Str', vim.NIL } },
                    { { '->', 'void', vim.NIL, vim.NIL } },
                    { 'core.lang.Public', tail = 'public' },
                    'Quick print line function.',
                    { 'Io.h', 242, 243 },
                    { { 'Members', { 'core.Str.+', tail = '+(core.Str) [public]' } } },
                },
            },
        }
        local encoded = Enc.enc_message(msg)
        local decoded, rest = Dec.dec_message(encoded)
        assert.are.same(msg, decoded)
        assert.are.equal('', rest)
    end)

    it('decodes an empty nested list as nil', function()
        local decoded = Dec.dec_message(Enc.enc_message({ sym 'documentation', vim.NIL }))
        assert.are.same({ sym 'documentation', vim.NIL }, decoded)
    end)

    it('skips a corrupt message and keeps decoding the next one', function()
        -- Valid length prefix, invalid tag 0x09 inside the body
        local corrupt = string.char(0x0, 0x0, 0x0, 0x0, 0x3, 0x1, 0x9, 0x0)
        local decoded, rest, err = Dec.dec_message(corrupt .. simple_serial)
        assert.is_nil(decoded)
        assert.is_string(err)
        assert.are.equal(simple_serial, rest)
        decoded, rest, err = Dec.dec_message(rest)
        assert.are.same(simple_deserial, decoded)
        assert.is_nil(err)
        assert.are.equal('', rest)
    end)

    it('reports an unknown symbol id as an error, not a crash', function()
        local msg = string.char(0x0, 0x0, 0x0, 0x0, 0x7, 0x1, 0x5, 0x0, 0x0, 0x0, 0x63, 0x0)
        local decoded, rest, err = Dec.dec_message(msg)
        assert.is_nil(decoded)
        assert.matches('unknown symbol', err)
        assert.are.equal('', rest)
    end)

    it('waits for a message split across reads', function()
        local buffer = ''
        local results = {}
        for i = 1, #simple_serial do
            buffer = buffer .. simple_serial:sub(i, i)
            local decoded, rest = Dec.dec_message(buffer)
            buffer = rest
            if decoded then table.insert(results, decoded) end
        end
        assert.are.same({ simple_deserial }, results)
    end)

    it('reuses symbol ids declared by Storm when encoding', function()
        -- Storm declares (color) with id 0x42
        local from_storm = string.char(
            0x0,
            0x0,
            0x0,
            0x0,
            0x10,
            0x1,
            0x4,
            0x0,
            0x0,
            0x0,
            0x42,
            0x0,
            0x0,
            0x0,
            0x5,
            0x63,
            0x6f,
            0x6c,
            0x6f,
            0x72,
            0x0
        )
        assert.are.same({ sym 'color' }, (Dec.dec_message(from_storm)))
        local encoded = Enc.enc_message({ sym 'color' })
        assert.are.equal(string.char(0x0, 0x0, 0x0, 0x0, 0x7, 0x1, 0x5, 0x0, 0x0, 0x0, 0x42, 0x0), encoded)
    end)
end)
