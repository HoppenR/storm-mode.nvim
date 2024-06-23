---@module "busted"

describe('messaging', function()
    local Dec = require('storm-mode.decoder')
    local Enc = require('storm-mode.encoder')
    local sym = require('storm-mode.sym').literal

    ---@type storm-mode.lsp.message
    local simple_deserial = { sym 'a', 10, sym 'a', 'b' }
    local simple_serial = string.char(
        0x0, 0x0, 0x0, 0x0, 0x1F,
        0x1, 0x4, 0x0, 0x0, 0x0, 0x1, 0x0, 0x0, 0x0, 0x1, 0x61,
        0x1, 0x2, 0x0, 0x0, 0x0, 0xA,
        0x1, 0x5, 0x0, 0x0, 0x0, 0x1,
        0x1, 0x3, 0x0, 0x0, 0x0, 0x1, 0x62, 0x0
    )

    ---@type storm-mode.lsp.message
    local nil_deserial = { sym 'debug', vim.NIL }
    local nil_serial = string.char(
        0x0, 0x0, 0x0, 0x0, 0x12,
        0x1, 0x4, 0x0, 0x0, 0x0, 0x1, 0x0, 0x0, 0x0, 0x5, 0x64, 0x65, 0x62, 0x75, 0x67,
        0x1, 0x0, 0x0
    )

    ---@type storm-mode.lsp.message
    local bignum_deserial = { 0x19203828 }
    local bignum_serial = string.char(
        0x0, 0x0, 0x0, 0x0, 0x7,
        0x1, 0x2, 0x19, 0x20, 0x38, 0x28, 0x0
    )

    before_each(function()
        Enc._next_symid = 1
    end)

    it('encodes sample', function()
        local encoded = Enc.enc_message(simple_deserial)
        assert.equals(simple_serial, encoded, 'should encode correctly')
    end)

    it('encodes vim.NIL in message', function()
        local encoded = Enc.enc_message(nil_deserial)
        assert.equals(nil_serial, encoded, 'should encode nil')
    end)

    it('encodes big number', function()
        local encoded = Enc.enc_message(bignum_deserial)
        assert.equals(bignum_serial, encoded)
    end)

    it('decodes sample', function()
        local decoded, rest = Dec.dec_message(simple_serial)
        assert.are.same(simple_deserial, decoded, 'should decode correctly')
        assert.equal(rest, '', 'should consume all characters')
    end)

    it('decodes nil in message', function()
        local decoded, rest = Dec.dec_message(nil_serial)
        assert.are.same(nil_deserial, decoded, 'should decode nil')
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
        assert.are.same(simple_deserial, decoded)
        assert.is_equal(rest, appended_str)
    end)

    it('returns nil on empty data', function()
        local decoded, rest = Dec.dec_message('')
        assert.is_nil(decoded)
        assert.is_equal(rest, '')
    end)
end)
