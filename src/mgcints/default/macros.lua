-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local require = require
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
local ParamAssert = require "mgcints.default.errors".ParamCheck

local SYMBOL = require "mgcints.default.symbols"
local Class = require "mgcints.util.class"
local Cmd = require "mgcints.mml.command"
local StringView = require "mgcints.util.stringview"
local MacroTable = require "mgcints.mml.macrotable"
local Builder = require "mgcints.mml.command.builder" ()
local Trie = require "mgcints.util.trie"
local Lexer = require "mgcints.default.lexers"

local create; do
  local RAW = Builder:setHandler(function (ch, ...)
    ch:addChunk(...)
  end):param "Uint8":param "Uint8":variadic():make()
  local CHANNEL = Builder:setSongHandler(function (song, t)
    song:setPseudoCh(nil)
    song:doAll(function (ch)
      ch:setActive(false)
    end)
    for k in pairs(t) do
      song:getChannel(k):setActive(true)
    end
  end):param "Channel":make()
  local COMMENT = Class({
    getParams = function (self, sv)
      sv:trim "[^\r\n]*"
    end,
  }, Cmd)
  local MULTI_COMMENT = Builder:param(function (sv)
    local b, e = sv:find(SYMBOL.MULTICOMMENT_END, 1, true)
    sv:advance(ParamAssert(e))
  end):make()
create = function ()
  local macrostr = Trie()
  local patternstr = Trie()

  local MacroDefineCmd = Class({
    getParams = function (self, sv)
      local name = ParamAssert(Lexer.Ident(sv))
      sv:trim "[ \t]*,?[ \t]*" -- do not trim newlines
      return name, sv:trim "[^\n]*"
    end,
    applySong = function (self, song, name, mmlstr)
      local cmdlist = {}
      local parser = song:getEngine():getParser()
      for _, cmd, params in parser:loop(StringView(mmlstr)) do
        insert(cmdlist, {cmd, params})
      end
      macrostr:add(name, cmdlist)
    end,
  }, Cmd)
  local MacroInvokeCmd = Class({
    getParams = function (self, sv)
      local k, list = macrostr:lookup(sv)
      ParamAssert(k, "Unknown macro name")
      sv:advance(#k)
      return list
    end,
    applySong = function (self, song, cmdlist)
      for _, v in ipairs(cmdlist) do
        local cmd, params = v[1], v[2]
        cmd:apply(song, params())
      end
    end,
  }, Cmd)
  local PatternDefineCmd = Builder:setSongHandler(function (song, id)
    song:setPseudoCh(id)
    patternstr:add(id)
  end):param "Ident":make()
  local PatternInvokeCmd = Builder:param(function (sv)
    local k = patternstr:lookup(sv)
    if k then
      sv:advance(#k)
      return k
    end
    local id = Lexer.Ident(sv)
    patternstr:add(id)
    return id
  end):make()

  local mtable = MacroTable()
  mtable:addCommand(SYMBOL.RAW_INSERT, RAW)
  mtable:addCommand(SYMBOL.CHANNELSELECT, CHANNEL)
  mtable:addCommand(SYMBOL.SINGLECOMMENT, COMMENT)
  mtable:addCommand(SYMBOL.MULTICOMMENT_BEGIN, MULTI_COMMENT)
  mtable:addCommand(SYMBOL.MACRODEFINE, MacroDefineCmd)
  mtable:addCommand(SYMBOL.MACROINVOKE, MacroInvokeCmd)
  mtable:addCommand(SYMBOL.PATTERNDEFINE, PatternDefineCmd)
  mtable:addCommand(SYMBOL.PATTERNINVOKE, PatternInvokeCmd)
  return mtable
end; end

return create
