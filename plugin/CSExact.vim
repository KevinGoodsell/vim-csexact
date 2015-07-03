" Vim global plugin to use GVim colorschemes with terminals
" Last Change: 2011 November 27
" Maintainer:  Kevin Goodsell <kevin-opensource@omegacrash.net>
" License:     GPL (see below)

" {{{ COPYRIGHT & LICENSE
"
" Copyright 2010, 2011 Kevin Goodsell
"
" This file is part of CSExact.
"
" CSExact is free software: you can redistribute it and/or modify it under
" the terms of the GNU General Public License as published by the Free Software
" Foundation, either version 3 of the License, or (at your option) any later
" version.
"
" CSExact is distributed in the hope that it will be useful, but WITHOUT
" ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
" FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
" details.
"
" You should have received a copy of the GNU General Public License along with
" CSExact.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}

if exists("loaded_csexact")
    finish
endif
let loaded_csexact = 1

" Not useful in the GUI, and doesn't work if Vim was built without GUI support
" prior to version 7.3.
if has("gui_running") || (!has("gui") && v:version < 703)
    finish
endif

let s:save_cpo = &cpo
set cpo&vim

" {{{ TERMINAL ABSTRACTION

function! s:TermFactory()
    let term = csexact#TermDetails(1)

    if get(term, 'multiplexer') =~# '\v^tmux'
        let tty = s:TtyFactoryTmux()
    elseif get(term, 'multiplexer') =~# '\v^screen'
        let tty = s:TtyFactoryScreen()
    else
        let tty = s:TtyFactory()
    endif

    if s:Colors() < 88 ||
            \ get(term, 'host_term') !~# '\v^(xterm|gnome|xfce|rxvt)' ||
            \ empty(tty)
        return {}
    endif

    " Special case: XTerm patch 252 and up supports OSC 104 to reset colors.
    if get(term, 'host_term') =~# '\v^xterm'
        let xterm_patch = str2nr(matchstr($XTERM_VERSION,
                                        \ '\v^XTerm\(\zs\d+\ze\)'))
    endif

    if exists("xterm_patch") && xterm_patch >= 252
        let Reset = function("s:TermResetColors_Osc104")
        let default_colors = {}
    else
        let colors = s:Colors()
        let Reset = function("s:TermResetColors_Defaults")
        if colors == 88
            let default_colors = g:csexactdata#xterm88
        elseif colors == 256
            let default_colors = g:csexactdata#xterm256
        else
            return {}
        endif
    endif

    return {
        \ "StartColors" : function("s:TermStartColors"),
        \ "RestartColors" : function("s:RestartColors"),
        \ "FinishColors" : function("s:TermFinishColors"),
        \ "AbortColors" : function("s:TermStartColors"),
        \ "GetColor" : function("s:TermGetColor"),
        \ "ResetColors" : Reset,
        \ "SetCursor" : function("s:TermSetCursor"),
        \ "ResetCursor" : function("s:TermResetCursor"),
        \ "tty" : tty,
        \ "PrivSetColor" : function("s:TermSetColor"),
        \ "_color_string" : [],
        \ "_color_string_len" : 0,
        \ "_colors" : {},
        \ "_next_color" : 16,
        \ "_default_colors" : default_colors,
    \ }
endfunction

function! s:TermStartColors() dict
    let self._color_string = []
    let self._color_string_len = 0
endfunction

function! s:RestartColors() dict
    let self._next_color = 16
    let self._colors = {}
    call self.StartColors()
endfunction

function! s:TermFinishColors() dict
    if !empty(self._color_string)
        call self.tty.SendCode(printf("\033]4%s\007",
                                    \ join(self._color_string, "")))
    endif
endfunction

function! s:TermSetColor(colorindex, colorname) dict
    let command = printf(";%d;%s", a:colorindex, a:colorname)
    " 4 bytes of overhead in the OSC command: ESC ] 4 at the beginning, BEL at
    " the end.
    if self._color_string_len + len(command) + 4 > self.tty.code_max
        call self.FinishColors()
        call self.StartColors()
    endif
    call add(self._color_string, command)
    let self._color_string_len += len(command)
endfunction

function! s:TermGetColor(colorname) dict
    if has_key(self._colors, a:colorname)
        return self._colors[a:colorname]
    endif

    if self._next_color >= s:Colors()
        throw "out of terminal colors"
    endif

    " The color number is tweaked a little so that the sequence of colors ends
    " up being (t_Co-1), 16, 17, 18.... The "Normal" group will usually get
    " assigned the first two, and therefore still be readable when colors get
    " reset (otherwise the foreground and background would use adjacent color
    " numbers and be very difficult to distinguish).
    let c = self._next_color - 1
    if c == 15
        let c = s:Colors() - 1
    endif
    let self._next_color += 1
    let self._colors[a:colorname] = c
    call self.PrivSetColor(c, a:colorname)

    return c
endfunction

function! s:TermResetColors_Defaults() dict
    call self.StartColors()

    for [cnum, color] in items(self._default_colors)
        call self.PrivSetColor(cnum, color)
    endfor

    call self.FinishColors()
endfunction

function! s:TermResetColors_Osc104() dict
    call self.tty.SendCode("\033]104\007")
endfunction

function! s:TermSetCursor(color) dict
    if a:color !~ '\v^(fg|bg|none)$'
        call self.tty.SendCode(printf("\033]12;%s\007", a:color))
    endif
endfunction

function! s:TermResetCursor() dict
    if exists("g:csexact_cursor_reset")
        call self.tty.SendCode(g:csexact_cursor_reset)
    endif
endfunction

" }}}
" {{{ TTY ABSTRACTION

function! s:TtyFactory()
    if filewritable("/dev/tty")
        let SendCode = function("s:TtySendCode_DevTty")
    else
        return {}
    endif

    " The max here is arbitrary. I haven't hit a true maximum.
    return {
        \ "SendCode" : SendCode,
        \ "code_max" : 4096,
    \ }
endfunction

function! s:TtySendCode_DevTty(code)
    call writefile([a:code], "/dev/tty", "b")
endfunction

function! s:TtyFactoryScreen()
    let base = s:TtyFactory()
    if empty(base)
        return {}
    endif

    " Screen has a builtin limit of 256 (with one reserved for NUL) for
    " control strings. See StringChar in ansi.c, and the definition of MAXSTR
    " in screen.h.
    " We tag on 4 extra bytes for each code sent to base.
    let code_max = min([255, base.code_max - 4])
    return {
        \ "SendCode" : function("s:TtySendCode_Screen"),
        \ "code_max" : code_max,
        \ "_base" : base,
    \ }
endfunction

function! s:TtyFactoryTmux()
    let base = s:TtyFactory()
    if empty(base)
        return {}
    endif

    " tmux uses a 256-byte input buffer (tmux.h, input_buf member of input_ctx)
    " with the last byte reserved for NUL. We start each send with the 7
    " characters ESC Ptmux; and end with ESC \. Of this, only the tmux; is
    " stored in tmux's input buffer, and therefore this only accounts for 5
    " bytes used up of the 255 byte limit. This means that the builtin limit for
    " TtyFactoryTmux is 250.
    let tmux_max = 250

    " All of this is sent through base, and we need to stay under its limit.
    " Therefore we subtract off the 7 leading bytes and 2 trailing bytes, then
    " divide by 2 based on the pessimistic assumption that all the other
    " characters will be ESC and will be doubled.
    let base_max = (base.code_max - 7 - 2) / 2

    let code_max = min([tmux_max, base_max])
    return {
        \ "SendCode" : function("s:TtySendCode_Tmux"),
        \ "code_max" : code_max,
        \ "_base" : base,
    \ }
endfunction

function! s:TtySendCode_Screen(code) dict
    " Screen's Device Control String (DCS) can be used to pass a command to
    " the host terminal, but it has limitations. First, it must be shorter
    " than 256 bytes. Second, there's no way to embed the String Terminator
    " sequence, ESC backslash. This appears to be a bug in the state machine
    " in ansi.c. It looks like a double-ESC should add an ESC to the output
    " without interpreting it, but it stays in the STRESC state afterward, so
    " it still interprets a following backslash as the end of the DCS.
    call self._base.SendCode(printf("\033P%s\033\\", a:code))
endfunction

function! s:TtySendCode_Tmux(code) dict
    " Double escapes. Note that even though this expands the output buffer, each
    " doubled escape is collapsed to a single escape character in tmux's input
    " buffer, therefore this won't push us over the 255 character limit. Of
    " course it *could* push over the limit for _base if we aren't careful (this
    " is accounted for in the calculation of the tmux code_max).
    let escaped = substitute(a:code, "\e", "\e\e", "g")
    call self._base.SendCode(printf("\ePtmux;%s\e\\", escaped))
endfunction

" }}}
" {{{ IMPLEMENTATION

function! s:CSExactErrorWrapper(func, ...)
    try
        call call(a:func, a:000)
    catch
        redraw
        echohl ErrorMsg
        echomsg "Error from: " . rethrow#Throwpoint()
        echomsg v:exception
        echohl NONE
    endtry
endfunction

function! s:Colors()
    return get(g:, "csexact_colors_override", &t_Co)
endfunction

function! s:CSExactRefresh()
    if empty(s:term)
        return
    endif

    let highlights = s:GetHighlights()
    let normal = get(highlights, "Normal", {})
    " Use defaults if no colors were given
    if !has_key(normal, "guifg")
        let normal.guifg = s:NormalizeColor(
            \ get(g:, "csexact_fg_default", "#000000"))
    endif
    if !has_key(normal, "guibg")
        let normal.guibg = s:NormalizeColor(
            \ get(g:, "csexact_bg_default", "#ffffff"))
    endif
    let highlights.Normal = normal

    " Try to infer 'background'. In a terminal Vim will set 'background' based
    " on Normal's ctermbg, but does so very naively and often incorrectly.
    let normalbg_rgb = matchlist(normal.guibg, '\v^#(\x\x)(\x\x)(\x\x)$')
    if empty(normalbg_rgb)
        echomsg "Warning: 'background' can't be inferred, might be incorrect"
        let background = "light"
    else
        let [r, g, b] = normalbg_rgb[1:3]
        " Luminance is calculated as Y = 0.2126 R + 0.7152 G + 0.0722 B
        let lum = 2126 * str2nr(r, 16) + 7152 * str2nr(g, 16)
              \ +  722 * str2nr(b, 16)
        " lum should be 0 to 2550000
        if lum < 1275000
            let background = "dark"
        else
            let background = "light"
        endif
    endif

    " Override normal color setting. "none" isn't a color, "fg" and "bg" are
    " not always available.
    let color_overrides = {"none" : "none"}
    let color_overrides.fg = normal.guifg == "none" ? "none" : "fg"
    let color_overrides.bg = normal.guibg == "none" ? "none" : "bg"

    " 'Normal' needs to be first so 'fg' and 'bg' are available.
    let group_names = keys(highlights)
    let normal_idx = index(group_names, "Normal")
    " Swap into first position.
    let [group_names[0], group_names[normal_idx]] =
      \ [group_names[normal_idx], group_names[0]]

    try
        call s:term.RestartColors()
        " g:colors_name needs to be unlet to prevent Vim from reloading the
        " colorscheme (or unloading it in some cases) when 'background'
        " changes (possibly as a result of the 'Normal' group's ctermbg being
        " set). See options.c did_set_string_option's handling of
        " 'background'.
        let save_colors_name = get(g:, "colors_name", "")
        unlet! g:colors_name
        try
            for name in group_names
                " Some items aren't used in the terminal, so don't waste
                " palette slots on them.
                if name =~ '\v^(Cursor|CursorIM|lCursor|Menu|ScrollBar|Tooltip)$'
                    continue
                endif

                let items = highlights[name]

                if has_key(items, "links_to")
                    exec printf("highlight! link %s %s", name, items.links_to)
                    continue
                endif

                call s:TermAttrs(name, items, color_overrides)

                " The first time through (after setting 'Normal'), fix
                " 'background'. Vim sets it incorrectly when Normal's ctermbg
                " is set.
                if exists("background")
                    let &background = background
                    unlet background
                endif

                " GUI items get reset when 'background' is changed, so fix
                " them.
                exec printf("highlight %s gui='%s' guifg='%s' guibg='%s' guisp='%s'",
                    \ name, join(get(items, "gui", ["NONE"]), ","),
                    \ get(items, "guifg", "NONE"),
                    \ get(items, "guibg", "NONE"),
                    \ get(items, "guisp", "NONE"))
            endfor
        finally
            if !empty(save_colors_name)
                let g:colors_name = save_colors_name
            endif
            call s:term.FinishColors()
        endtry

        " Set cursor color if the color scheme supports it. Otherwise reset to
        " default.
        if has_key(g:, "csexact_cursor_reset")
            let color = s:ResolveColor("Cursor", "guibg", highlights)

            if color != ""
                call s:term.SetCursor(color)
            else
                call s:term.ResetCursor()
            endif
        endif
    catch
        call s:CSExactReset()
        call rethrow#Rethrow()
    endtry
endfunction

function! s:GetHighlights()
    " Extend columns temporarily to prevent line wrapping in messages. Also turn
    " off verbose temporarily to prevent unwanted messages.
    let [saved_columns, saved_verbose] = [&columns, &verbose]
    set columns=99999 verbose=0

    redir => hltext
    silent highlight
    redir END

    " Restore columns and verbose.
    let [&columns, &verbose] = [saved_columns, saved_verbose]

    let hlgroups = split(hltext, '\n')

    let result = {} " {'GroupName' : info_dict}
    let i = 0
    while i < len(hlgroups)
        let group = hlgroups[i]
        let i += 1

        " Theoretically the group name could consist of any printable
        " characters. Not sure about whitespace.
        let parts = matchlist(group, '\v^(\S+) +xxx (.*)$')
        if empty(parts)
            echomsg printf("CSExact: Bad highlight line '%s'", group)
            continue
        endif

        let [name, item_string] = parts[1:2]

        " Cleared?
        if item_string == "cleared"
            let result[name] = {}
            continue
        endif

        " Links To...?
        let parts = matchlist(item_string, '\v^links to (\S+)$')
        if !empty(parts)
            let result[name] = { "links_to" : parts[1] }
            continue
        endif

        let items = {}

        " Key-Value items
        for kv in split(item_string, '\v \ze\w+\=')
            let [key, value] = matchlist(kv, '\v(\w+)\=(.*)')[1:2]

            if key =~ '\v(fg|bg|sp)$'
                " Handle color
                let norm = s:NormalizeColor(value)
                let items[key] = norm
            elseif key =~ '\v^(gui|cterm)$'
                " Handle attributes
                let items[key] = split(value, ",")
            endif
        endfor

        " It's possible to have both specific attributes (term=..., etc.) and
        " also have a link. This can be done by setting attributes, then using
        " :highlight! link GroupName AnotherGroupName. In the :highlight output
        " it looks like this:
        "
        " SpellLocal     xxx term=underline ctermbg=14 gui=undercurl guisp=Cyan
        "                links to Error
        "
        " Here we look ahead to see if there's an "links to" on the next line.

        if i < len(hlgroups)
            let parts = matchlist(hlgroups[i], '\v^\s+ links to (\S+)$')
            if !empty(parts)
                let items.links_to = parts[1]
                let i += 1
            endif
        endif

        let result[name] = items
    endwhile

    return result
endfunction

function! s:NormalizeColor(color)
    let lower_color = tolower(a:color)

    if lower_color == "bg" || lower_color == "background"
        return "bg"
    elseif lower_color == "fg" || lower_color == "foreground"
        return "fg"
    elseif lower_color == "none"
        return "none"
    endif

    return get(g:csexactdata#color_names, lower_color, lower_color)
endfunction

function! s:ResolveLinks(groupname, highlights)
    let groupname = a:groupname
    let max_levels = 20
    for i in range(max_levels)
        let group = get(a:highlights, groupname, {})
        if has_key(group, "links_to")
            let groupname = group.links_to
        else
            return group
        endif
    endfor
    return {}
endfunction

function! s:ResolveColor(groupname, key, highlights)
    let group = s:ResolveLinks(a:groupname, a:highlights)
    let color = get(group, a:key, "")
    if color =~ '\v^(fg|bg)$'
        let norm = get(a:highlights, "Normal", {})
        if color == "fg"
            let color = get(norm, "guifg", "")
        else
            let color = get(norm, "guibg", "")
        endif
    endif
    return color
endfunction

function! s:TermAttrs(name, items, color_overrides)
    exec printf("highlight %s cterm=NONE ctermfg=NONE ctermbg=NONE", a:name)

    " Retrieve, but don't set attributes
    let attrs = get(a:items, "gui", [])
    let supported_attr = '\v^(bold|underline|reverse|standout)$'
    let cterm_attrs = filter(copy(attrs), "v:val =~ supported_attr")

    " Use underline to replace undercurl
    let undercurl = index(attrs, "undercurl") >= 0
    if undercurl
        call add(cterm_attrs, "underline")
    endif

    " Foreground, using guisp or guifg depending on the presence of undercurl
    if undercurl && has_key(a:items, "guisp")
        call s:TermColor(a:name, a:items.guisp, "fg", a:color_overrides)
    elseif has_key(a:items, "guifg")
        call s:TermColor(a:name, a:items.guifg, "fg", a:color_overrides)
    endif

    " Background
    if has_key(a:items, "guibg")
        call s:TermColor(a:name, a:items.guibg, "bg", a:color_overrides)
    endif

    " Finally set attributes
    if empty(cterm_attrs)
        let cterm_attrs = ["NONE"]
    endif
    exec printf("highlight %s cterm=%s", a:name, join(cterm_attrs, ","))
endfunction

function! s:TermColor(name, color, ground, color_overrides)
    if has_key(a:color_overrides, a:color)
        let term_color = a:color_overrides[a:color]
    else
        let term_color = s:term.GetColor(a:color)
    endif
    exec printf("highlight %s cterm%s=%s", a:name, a:ground, term_color)
endfunction

" Implementation of the CSExactColors command
function! s:CSExactColors()
    if empty(s:term)
        echoerr "CSExact not supported"
        return
    endif

    call s:CSExactErrorWrapper("s:CSExactRefresh")
endfunction

" Similar to s:CSExactColors(), but called for startup and colorscheme changes.
function! s:CSExactCheck()
    " Remove CSApprox autocmd if it exists. We'll handle the event here.
    if exists("#CSApprox#ColorScheme")
        autocmd! CSApprox
    endif

    if empty(s:term)
        " CSExact not supported
        let use_csexact = 0
    elseif get(g:, "colors_name", "NOCOLORSCHEME") =~
        \ get(g:, "csexact_blacklist", '\v^$')
        " Colorscheme blacklisted
        CSExactResetColors
        let use_csexact = 0
    else
        let use_csexact = 1
    endif

    if use_csexact
        call s:CSExactErrorWrapper("s:CSExactRefresh")
    else
        " Attempt to invoke CSApprox to handle this case.
        call s:CallCSApprox()
    endif
endfunction

function! s:CSExactReset()
    if empty(s:term)
        return
    endif

    call s:term.ResetColors()
    call s:term.ResetCursor()

    let s:term._colors = {}
    let s:term._next_color = 16
endfunction

" Attempt to find and invoke CSApprox(), which is a script-local function in
" CSApprox.
function! s:CallCSApprox()
    if !exists(":CSApproxSnapshot")
        " CSApprox not loaded.
        return
    endif

    if !exists("s:csapprox_func")
        redir => functions
        silent function
        redir END

        let s:csapprox_func = matchstr(functions, '\v\<SNR\>\d+_CSApprox\ze\(')
    endif

    if !empty(s:csapprox_func)
        call call(s:csapprox_func, [])
    endif
endfunction

" }}}
" {{{ COMMANDS

augroup CSExact
    autocmd!
    autocmd VimLeave * CSExactResetColors
    autocmd ColorScheme * call s:CSExactCheck()
    " Unfortunately we can't reset the colors before going into the GUI, but
    " remove the autocmds since they are meaningless (and broken) in the GUI.
    autocmd GUIEnter * au! CSExact
augroup END

if !exists(":CSExactColors")
    command! -bar CSExactColors call s:CSExactColors()
endif
if !exists(":CSExactResetColors")
    command! -bar CSExactResetColors call s:CSExactErrorWrapper("s:CSExactReset")
endif

" }}}

let s:term = s:TermFactory()

call s:CSExactCheck()

let &cpo = s:save_cpo
