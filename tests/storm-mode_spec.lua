local describe = require('plenary.busted').describe
local it = require('plenary.busted').it

describe('messaging', function()
    local Dec = require('storm-mode.decoder')
    local Enc = require('storm-mode.encoder')
    local sym = require('storm-mode.sym').literal

    ---@type storm-mode.lsp.message
    local simple_deserial = { sym 'a', 10, sym 'a', 'b' }
    local simple_serial = string.char(
        0x00, 0x00, 0x00, 0x00, 0x1F,
        0x01, 0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x61,
        0x01, 0x02, 0x00, 0x00, 0x00, 0x0A,
        0x01, 0x05, 0x00, 0x00, 0x00, 0x01,
        0x01, 0x03, 0x00, 0x00, 0x00, 0x01, 0x62, 0x00
    )

    it('encodes sample', function()
        local encoded = Enc.enc_message(simple_deserial)
        assert.equals(simple_serial, encoded, 'should encode correctly')
    end)

    it('decodes sample', function()
        local decoded, rest = Dec.dec_message(simple_serial)
        assert.are.same(simple_deserial, decoded, 'should decode correctly')
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
end)

describe('lsp', function()
    before_each(function()
        -- Restart LSP here...
        -- needs a proper waiting-to-start mechanism first
    end)
end)
