" Vim global plugin to use GVim colorschemes with terminals
" Last Change: 2010 Dec 25
" Maintainer:  Kevin Goodsell <kevin-opensource@omegacrash.net>
" License:     GPL (see below)

" {{{ COPYRIGHT & LICENSE
"
" Copyright 2010 Kevin Goodsell
"
" This program is free software: you can redistribute it and/or modify it under
" the terms of the GNU General Public License as published by the Free Software
" Foundation, either version 3 of the License, or (at your option) any later
" version.
"
" This program is distributed in the hope that it will be useful, but WITHOUT
" ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
" FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
" details.
"
" You should have received a copy of the GNU General Public License along with
" this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}
" {{{ NOTES
"
" This plugin allows the use of GUI (GVim) color schemes in (some) terminals.
" This is done by using terminal magic to modify the terminal's color palette
" on startup and each time a color scheme is loaded.
"
" Supported Terminals:
"
"   Currently GNOME Terminal, xterm, and rxvt are supported. For all
"   terminals, at least 88 color support is required. The intent is to support
"   additional terminals in future releases.
"
" Issues:
"
"   There are some inherent issues in this method of setting Vim's colors.
"
"   * It obviously only works with terminals that support changing the palette.
"   * The colors are modified in the terminal itself. This will affect other
"     terminal applications. The "system colors" (colors 0 to 15) are never
"     changed, which helps minimize this problem.
"   * The terminal colors are reset when Vim exits, but this can create other
"     problems:
"     - If a running Vim is suspended, and a new instance is started then
"       terminated, the colors will be reset by the second instance. When the
"       first instance is resumed, the colors will be wrong.
"     - There's no reliable way to reset the colors, so in most cases they
"       will simply be set to pre-defined defaults. These defaults may not
"       match the user's settings.
"   * If Vim exits abnormally, and the VimLeave autocommands are not executed,
"     the colors will not be restored. In particular, when the user moves to a
"     GUI with :gvim or :gui, the terminal colors are not restored.
"   * Proper handling of colors depends on the color scheme actually setting
"     GUI colors properly. Some color schemes will check for a terminal Vim
"     session and not set GUI colors in that case.
"
" Thanks:
"
"   Special thanks to Matt Wozniski (godlygeek on github) for writing
"   CSApprox, the primary inspiration for this plugin.
"
" }}}
" {{{ USAGE
"
" Install this file in a plugin/ sub-directory in your runtimepath (typically
" ~/.vim/plugin, or ~/.vim/bundle/CSExact/ if you use the pathogen plugin).
"
" After installation, the plugin will function automatically via autocommands.
" You can use explicit commands also, when necessary.
"
" Commands:
"
"   :CSExactColors
"
"     Sets terminal palette and Vim colors based on the GUI colors of the
"     current color scheme. This can be run at any time to update the colors,
"     but is usually run automatically. Running this explicitly can repair
"     incorrect colors caused by reseting the palette.
"
"   :CSExactResetColors
"
"     Resets the terminal palette. This is invoked automatically on exit, and
"     usually shouldn't be needed.
"
" Configuration Options:
"
"   g:csexact_term_override
"
"     Set the terminal name. Uses 'term' setting if unset.
"
"   g:csexact_colors_override
"
"     Set the number of terminal colors. Uses 't_Co' if unset.
"
"   g:csexact_blacklist
"
"     This is a pattern describing colorscheme names that should not be
"     colorized with CSExact.
"
" }}}

if exists("loaded_csexact")
    finish
endif
let loaded_csexact = 1

let s:save_cpo = &cpo
set cpo&vim

" Not useful in the GUI, doesn't work without a tty device, and doesn't work
" if Vim was built without GUI support prior to version 7.3.
if has("gui_running") || !filewritable("/dev/tty")
        \ || (!has("gui") && v:version < 703)
    let &cpo = s:save_cpo
    finish
endif

" NOTES
" * Can also use \033]12;spec\007 to set cursor color, not sure how to
"   reset.

" TODO
" * Refactor for multiple terminals, add Screen support (use ESC P)
" * Refactor highlight reading, create more useful representation of highlight
"   items.

" XXX Problems
" - Anything missing in the GUI might be ugly in the terminal, and some things
"   are terminal-only.
" - 'shine' Statement group is weird due to special terminal handling.

" {{{ Tools to support 'rethrow' in Vim

let s:rethrow_pattern = '\v\<SNR\>\d+_Rethrow>'

function! s:Rethrow()
    let except = v:exception

    " Save source info
    if !exists("s:rethrow_throwpoint") || v:throwpoint !~# s:rethrow_pattern
        let s:rethrow_throwpoint = v:throwpoint
    endif

    " Can't directly throw Vim exceptions (see :h try-echoerr), so use echoerr
    " instead, but strip off an existing echoerr prefix first.
    if except =~# '\v^Vim'
        echoerr substitute(except, '\v^Vim\(echoerr\):', "", "")
    endif

    throw except
endfunction

function! s:Throwpoint()
    if v:throwpoint =~# s:rethrow_pattern
        return s:rethrow_throwpoint
    else
        return v:throwpoint
    endif
endfunction

" }}}

function! s:CSExactErrorWrapper(func, ...)
    try
        call call(a:func, a:000)
    catch
        redraw
        echohl ErrorMsg
        echomsg "Error from: " . s:Throwpoint()
        echomsg v:exception
        echohl NONE
    endtry
endfunction

function! s:Term()
    return get(g:, "csexact_term_override", &term)
endfunction

function! s:Colors()
    return get(g:, "csexact_colors_override", &t_Co)
endfunction

function! s:Supported()
    return s:Colors() >= 88 && s:Term() =~# '\v^(xterm|gnome|rxvt)'
endfunction

function! s:CSExactRefresh()
    if !s:Supported()
        return
    endif

    redir => hltext
    silent highlight
    redir END

    " :highlight wraps, need to unwrap.
    let hltext = substitute(hltext, '\v\n +', " ", "g")
    let hlgroups = split(hltext, '\n')

    " Some items aren't used in the terminal, so don't waste colors on them.
    let gui_only = '\v\c^(Cursor|CursorIM|lCursor|Menu|ScrollBar|Tooltip) '
    call filter(hlgroups, "v:val !~ gui_only")

    " Need to do special stuff with Normal. For one thing, it has to come
    " first to allow the 'fg' and 'bg' pseudo-colors.
    let norm_idx = match(hlgroups, '\v^Normal\s')
    if norm_idx >= 0
        let normal = remove(hlgroups, norm_idx)
    else
        let normal = ""
    endif

    if normal !~? '\vguifg\=' || normal !~? '\vguibg\='
        throw "Normal highlight group missing or incomplete"
    endif

    let normalbg = matchstr(normal, '\vguibg\=\zs#?(\w|\s)+\ze($| \w+\=)')
    let normalbg = s:NormalizeColor(normalbg)
    let normalbg_rgb = matchlist(normalbg, '\v^#(\x\x)(\x\x)(\x\x)')
    if empty(normalbg_rgb)
        echomsg "Warning: 'background' can't be inferred, might be incorrect"
        let background = "light"
    else
        let [r, g, b] = normalbg_rgb[1:3]
        " Luminence is calculated as Y = 0.2126 R + 0.7152 G + 0.0722 B
        let lum = 2126 * str2nr(r, 16) + 7152 * str2nr(g, 16)
              \ +  722 * str2nr(b, 16)
        " lum should be 0 to 2550000
        if lum < 1275000
            let background = "dark"
        else
            let background = "light"
        endif
    endif

    " Put normal in the front.
    call insert(hlgroups, normal)

    " XXX This is a good candidate for splitting into a new function.
    try
        call s:RestartColors()
        " g:colors_name needs to be unlet to prevent Vim from reloading the
        " colorscheme (or unloading it in some cases) when 'background'
        " changes (possibly as a result of the 'Normal' group's ctermbg being
        " set). See options.c did_set_string_option's handling of
        " 'background'.
        let save_colors_name = g:colors_name
        unlet g:colors_name
        try
            for group in hlgroups
                let parts = matchlist(group, '\v^(\w+) +xxx (.*)$')
                if empty(parts)
                    continue
                endif
                let [name, item_string] = parts[1:2]
                if item_string =~# '\v(^| )links to |^cleared$'
                    continue
                endif

                let item_list = split(item_string, '\v \ze\w+\=')
                let item_dict = {}
                for item in item_list
                    let [key, value] = matchlist(item, '\v^(\w+)\=(.*)$')[1:2]
                    let item_dict[key] = value
                endfor

                call s:TermAttrs(name, item_dict)

                " The first time through (after setting 'Normal'), fix
                " 'background'. Vim sets it incorrectly when Normal's ctermbg
                " is set.
                if exists("background")
                    let &background = background
                    unlet background
                endif

                " GUI items get reset when 'background' is changed, so fix
                " them.
                exec printf("hi %s gui='%s' guifg='%s' guibg='%s' guisp='%s'",
                    \ name, get(item_dict, "gui", "NONE"),
                    \ get(item_dict, "guifg", "NONE"),
                    \ get(item_dict, "guibg", "NONE"),
                    \ get(item_dict, "guisp", "NONE"))
            endfor
        finally
            let g:colors_name = save_colors_name
            call s:FinishColors()
        endtry
    catch
        call s:Reset()
        call s:Rethrow()
    endtry
endfunction

function s:CSExactCheckColorscheme()
    if exists("g:colors_name")
        \ && g:colors_name =~ get(g:, "csexact_blacklist", '\v^$')
        CSExactResetColors
    else
        CSExactColors
    endif
endfunction

function! s:TermAttrs(name, items)
    exec printf("hi %s cterm=NONE ctermfg=NONE ctermbg=NONE", a:name)

    " Retrieve, but don't set attributes
    if has_key(a:items, "gui")
        let attrs = split(a:items["gui"], ',')
        let supported_attr = '\v^(bold|underline|reverse)$'
        let cterm_attrs = filter(copy(attrs), "v:val =~ supported_attr")
    else
        let attrs = []
        let cterm_attrs = []
    endif

    " Foreground, using guisp or guifg depending on the presence of undercurl
    if match(attrs, '\v^undercurl$') >= 0
        call add(cterm_attrs, "underline")
        if has_key(a:items, "guisp")
            call s:TermColor(a:name, a:items["guisp"], "fg")
        endif
    elseif has_key(a:items, "guifg")
        call s:TermColor(a:name, a:items["guifg"], "fg")
    endif

    " Background
    if has_key(a:items, "guibg")
        call s:TermColor(a:name, a:items["guibg"], "bg")
    endif

    " Finally set attributes
    if empty(cterm_attrs)
        let cterm_attrs = ['NONE']
    endif
    exec printf("hi %s cterm=%s", a:name, join(cterm_attrs, ","))
endfunction

function! s:TermColor(name, color, ground)
    " 'foreground' works in the GUI but it has to be 'fg' in the terminal.
    if a:color =~? '\v^(fg|foreground)$'
        let term_color = "fg"
    elseif a:color =~? '\v^(bg|background)$'
        let term_color = "bg"
    elseif a:color =~? '\v^none$'
        let term_color = "none"
    else
        let term_color = s:GetColor(a:color)
    endif
    exec printf("hi %s cterm%s=%s", a:name, a:ground, term_color)
endfunction

" {{{ COLOR HANDLING

" Public portion:

function! s:StartColors()
    let s:color_string = []
endfunction

function! s:RestartColors()
    let s:next_color = 16
    let s:colors = {}
    call s:StartColors()
endfunction

function! s:FinishColors()
    if !empty(s:color_string)
        call s:SendCode(printf("\033]4%s\007", join(s:color_string, "")))
    endif
endfunction

function! s:GetColor(colorname)
    let colorname = s:NormalizeColor(a:colorname)
    if has_key(s:colors, colorname)
        return s:colors[colorname]
    endif

    if s:next_color >= s:Colors()
        throw "out of terminal colors"
    endif

    let c = s:next_color
    let s:next_color += 1
    let s:colors[colorname] = c
    call s:SetColor(c, colorname)

    return c
endfunction

function! s:CSExactReset()
    if !s:Supported()
        return
    endif

    " Special case: XTerm patch 252 and up supports OSC 104 to reset colors.
    if s:Term() =~# '\v^xterm'
        let xterm_patch = str2nr(matchstr($XTERM_VERSION,
                                        \ '\v^XTerm\(\zs\d+\ze\)'))
    endif

    if exists("xterm_patch") && xterm_patch >= 252
        call s:SendCode("\033]104\007")
    else
        call s:StartColors()

        if s:Colors() == 88
            let defaults = s:xterm88
        elseif s:Colors() == 256
            let defaults = s:xterm256
        else
            " No idea what defaults to use here.
            let defaults = {}
        endif

        for [cnum, color] in items(defaults)
            call s:SetColor(cnum, color)
        endfor

        call s:FinishColors()
    endif

    let s:colors = {}
    let s:next_color = 16
endfunction

" Internal (non-public) portion:

let s:colors = {} " { 'color_spec' : color_num }
let s:next_color = 16

function! s:SendCode(code)
    call writefile([a:code], "/dev/tty", "b")
endfunction

function! s:SetColor(c, colorname)
    " The Xterm color-setting command is '\033]4;c;spec\007', where c is the
    " color number and spec is in a format accepted by XParseColor. This
    " accepts colors that Vim accepts.
    let command = printf(';%d;%s', a:c, a:colorname)
    call add(s:color_string, command)
endfunction

function! s:NormalizeColor(color)
    let color = tolower(a:color)
    if has_key(s:color_names, color)
        return s:color_names[color]
    else
        return color
    endif
endfunction

" }}}

augroup CSExact
    autocmd!
    autocmd VimLeave * CSExactResetColors
    autocmd VimEnter,ColorScheme,TermChanged * call s:CSExactCheckColorscheme()
augroup END

command! -bar CSExactColors call s:CSExactErrorWrapper("s:CSExactRefresh")
command! -bar CSExactResetColors call s:CSExactErrorWrapper("s:CSExactReset")

" {{{ Data

" From Vim source, gui_x11.c
let s:color_names = {
    \ "lightred"     : "#ffbbbb",
    \ "lightgreen"   : "#88ff88",
    \ "lightmagenta" : "#ffbbff",
    \ "darkcyan"     : "#008888",
    \ "darkblue"     : "#0000bb",
    \ "darkred"      : "#bb0000",
    \ "darkmagenta"  : "#bb00bb",
    \ "darkgrey"     : "#bbbbbb",
    \ "darkyellow"   : "#bbbb00",
    \ "gray10"       : "#1a1a1a",
    \ "grey10"       : "#1a1a1a",
    \ "gray20"       : "#333333",
    \ "grey20"       : "#333333",
    \ "gray30"       : "#4d4d4d",
    \ "grey30"       : "#4d4d4d",
    \ "gray40"       : "#666666",
    \ "grey40"       : "#666666",
    \ "gray50"       : "#7f7f7f",
    \ "grey50"       : "#7f7f7f",
    \ "gray60"       : "#999999",
    \ "grey60"       : "#999999",
    \ "gray70"       : "#b3b3b3",
    \ "grey70"       : "#b3b3b3",
    \ "gray80"       : "#cccccc",
    \ "grey80"       : "#cccccc",
    \ "gray90"       : "#e5e5e5",
    \ "grey90"       : "#e5e5e5",
\ }

" From xterm source, 256colres.h
let s:xterm256 = {
    \ 16  : "#000000",
    \ 17  : "#00005f",
    \ 18  : "#000087",
    \ 19  : "#0000af",
    \ 20  : "#0000d7",
    \ 21  : "#0000ff",
    \ 22  : "#005f00",
    \ 23  : "#005f5f",
    \ 24  : "#005f87",
    \ 25  : "#005faf",
    \ 26  : "#005fd7",
    \ 27  : "#005fff",
    \ 28  : "#008700",
    \ 29  : "#00875f",
    \ 30  : "#008787",
    \ 31  : "#0087af",
    \ 32  : "#0087d7",
    \ 33  : "#0087ff",
    \ 34  : "#00af00",
    \ 35  : "#00af5f",
    \ 36  : "#00af87",
    \ 37  : "#00afaf",
    \ 38  : "#00afd7",
    \ 39  : "#00afff",
    \ 40  : "#00d700",
    \ 41  : "#00d75f",
    \ 42  : "#00d787",
    \ 43  : "#00d7af",
    \ 44  : "#00d7d7",
    \ 45  : "#00d7ff",
    \ 46  : "#00ff00",
    \ 47  : "#00ff5f",
    \ 48  : "#00ff87",
    \ 49  : "#00ffaf",
    \ 50  : "#00ffd7",
    \ 51  : "#00ffff",
    \ 52  : "#5f0000",
    \ 53  : "#5f005f",
    \ 54  : "#5f0087",
    \ 55  : "#5f00af",
    \ 56  : "#5f00d7",
    \ 57  : "#5f00ff",
    \ 58  : "#5f5f00",
    \ 59  : "#5f5f5f",
    \ 60  : "#5f5f87",
    \ 61  : "#5f5faf",
    \ 62  : "#5f5fd7",
    \ 63  : "#5f5fff",
    \ 64  : "#5f8700",
    \ 65  : "#5f875f",
    \ 66  : "#5f8787",
    \ 67  : "#5f87af",
    \ 68  : "#5f87d7",
    \ 69  : "#5f87ff",
    \ 70  : "#5faf00",
    \ 71  : "#5faf5f",
    \ 72  : "#5faf87",
    \ 73  : "#5fafaf",
    \ 74  : "#5fafd7",
    \ 75  : "#5fafff",
    \ 76  : "#5fd700",
    \ 77  : "#5fd75f",
    \ 78  : "#5fd787",
    \ 79  : "#5fd7af",
    \ 80  : "#5fd7d7",
    \ 81  : "#5fd7ff",
    \ 82  : "#5fff00",
    \ 83  : "#5fff5f",
    \ 84  : "#5fff87",
    \ 85  : "#5fffaf",
    \ 86  : "#5fffd7",
    \ 87  : "#5fffff",
    \ 88  : "#870000",
    \ 89  : "#87005f",
    \ 90  : "#870087",
    \ 91  : "#8700af",
    \ 92  : "#8700d7",
    \ 93  : "#8700ff",
    \ 94  : "#875f00",
    \ 95  : "#875f5f",
    \ 96  : "#875f87",
    \ 97  : "#875faf",
    \ 98  : "#875fd7",
    \ 99  : "#875fff",
    \ 100 : "#878700",
    \ 101 : "#87875f",
    \ 102 : "#878787",
    \ 103 : "#8787af",
    \ 104 : "#8787d7",
    \ 105 : "#8787ff",
    \ 106 : "#87af00",
    \ 107 : "#87af5f",
    \ 108 : "#87af87",
    \ 109 : "#87afaf",
    \ 110 : "#87afd7",
    \ 111 : "#87afff",
    \ 112 : "#87d700",
    \ 113 : "#87d75f",
    \ 114 : "#87d787",
    \ 115 : "#87d7af",
    \ 116 : "#87d7d7",
    \ 117 : "#87d7ff",
    \ 118 : "#87ff00",
    \ 119 : "#87ff5f",
    \ 120 : "#87ff87",
    \ 121 : "#87ffaf",
    \ 122 : "#87ffd7",
    \ 123 : "#87ffff",
    \ 124 : "#af0000",
    \ 125 : "#af005f",
    \ 126 : "#af0087",
    \ 127 : "#af00af",
    \ 128 : "#af00d7",
    \ 129 : "#af00ff",
    \ 130 : "#af5f00",
    \ 131 : "#af5f5f",
    \ 132 : "#af5f87",
    \ 133 : "#af5faf",
    \ 134 : "#af5fd7",
    \ 135 : "#af5fff",
    \ 136 : "#af8700",
    \ 137 : "#af875f",
    \ 138 : "#af8787",
    \ 139 : "#af87af",
    \ 140 : "#af87d7",
    \ 141 : "#af87ff",
    \ 142 : "#afaf00",
    \ 143 : "#afaf5f",
    \ 144 : "#afaf87",
    \ 145 : "#afafaf",
    \ 146 : "#afafd7",
    \ 147 : "#afafff",
    \ 148 : "#afd700",
    \ 149 : "#afd75f",
    \ 150 : "#afd787",
    \ 151 : "#afd7af",
    \ 152 : "#afd7d7",
    \ 153 : "#afd7ff",
    \ 154 : "#afff00",
    \ 155 : "#afff5f",
    \ 156 : "#afff87",
    \ 157 : "#afffaf",
    \ 158 : "#afffd7",
    \ 159 : "#afffff",
    \ 160 : "#d70000",
    \ 161 : "#d7005f",
    \ 162 : "#d70087",
    \ 163 : "#d700af",
    \ 164 : "#d700d7",
    \ 165 : "#d700ff",
    \ 166 : "#d75f00",
    \ 167 : "#d75f5f",
    \ 168 : "#d75f87",
    \ 169 : "#d75faf",
    \ 170 : "#d75fd7",
    \ 171 : "#d75fff",
    \ 172 : "#d78700",
    \ 173 : "#d7875f",
    \ 174 : "#d78787",
    \ 175 : "#d787af",
    \ 176 : "#d787d7",
    \ 177 : "#d787ff",
    \ 178 : "#d7af00",
    \ 179 : "#d7af5f",
    \ 180 : "#d7af87",
    \ 181 : "#d7afaf",
    \ 182 : "#d7afd7",
    \ 183 : "#d7afff",
    \ 184 : "#d7d700",
    \ 185 : "#d7d75f",
    \ 186 : "#d7d787",
    \ 187 : "#d7d7af",
    \ 188 : "#d7d7d7",
    \ 189 : "#d7d7ff",
    \ 190 : "#d7ff00",
    \ 191 : "#d7ff5f",
    \ 192 : "#d7ff87",
    \ 193 : "#d7ffaf",
    \ 194 : "#d7ffd7",
    \ 195 : "#d7ffff",
    \ 196 : "#ff0000",
    \ 197 : "#ff005f",
    \ 198 : "#ff0087",
    \ 199 : "#ff00af",
    \ 200 : "#ff00d7",
    \ 201 : "#ff00ff",
    \ 202 : "#ff5f00",
    \ 203 : "#ff5f5f",
    \ 204 : "#ff5f87",
    \ 205 : "#ff5faf",
    \ 206 : "#ff5fd7",
    \ 207 : "#ff5fff",
    \ 208 : "#ff8700",
    \ 209 : "#ff875f",
    \ 210 : "#ff8787",
    \ 211 : "#ff87af",
    \ 212 : "#ff87d7",
    \ 213 : "#ff87ff",
    \ 214 : "#ffaf00",
    \ 215 : "#ffaf5f",
    \ 216 : "#ffaf87",
    \ 217 : "#ffafaf",
    \ 218 : "#ffafd7",
    \ 219 : "#ffafff",
    \ 220 : "#ffd700",
    \ 221 : "#ffd75f",
    \ 222 : "#ffd787",
    \ 223 : "#ffd7af",
    \ 224 : "#ffd7d7",
    \ 225 : "#ffd7ff",
    \ 226 : "#ffff00",
    \ 227 : "#ffff5f",
    \ 228 : "#ffff87",
    \ 229 : "#ffffaf",
    \ 230 : "#ffffd7",
    \ 231 : "#ffffff",
    \ 232 : "#080808",
    \ 233 : "#121212",
    \ 234 : "#1c1c1c",
    \ 235 : "#262626",
    \ 236 : "#303030",
    \ 237 : "#3a3a3a",
    \ 238 : "#444444",
    \ 239 : "#4e4e4e",
    \ 240 : "#585858",
    \ 241 : "#626262",
    \ 242 : "#6c6c6c",
    \ 243 : "#767676",
    \ 244 : "#808080",
    \ 245 : "#8a8a8a",
    \ 246 : "#949494",
    \ 247 : "#9e9e9e",
    \ 248 : "#a8a8a8",
    \ 249 : "#b2b2b2",
    \ 250 : "#bcbcbc",
    \ 251 : "#c6c6c6",
    \ 252 : "#d0d0d0",
    \ 253 : "#dadada",
    \ 254 : "#e4e4e4",
    \ 255 : "#eeeeee",
\ }

" From xterm source, 88colres.h
let s:xterm88 = {
    \ 16 : "#000000",
    \ 17 : "#00008b",
    \ 18 : "#0000cd",
    \ 19 : "#0000ff",
    \ 20 : "#008b00",
    \ 21 : "#008b8b",
    \ 22 : "#008bcd",
    \ 23 : "#008bff",
    \ 24 : "#00cd00",
    \ 25 : "#00cd8b",
    \ 26 : "#00cdcd",
    \ 27 : "#00cdff",
    \ 28 : "#00ff00",
    \ 29 : "#00ff8b",
    \ 30 : "#00ffcd",
    \ 31 : "#00ffff",
    \ 32 : "#8b0000",
    \ 33 : "#8b008b",
    \ 34 : "#8b00cd",
    \ 35 : "#8b00ff",
    \ 36 : "#8b8b00",
    \ 37 : "#8b8b8b",
    \ 38 : "#8b8bcd",
    \ 39 : "#8b8bff",
    \ 40 : "#8bcd00",
    \ 41 : "#8bcd8b",
    \ 42 : "#8bcdcd",
    \ 43 : "#8bcdff",
    \ 44 : "#8bff00",
    \ 45 : "#8bff8b",
    \ 46 : "#8bffcd",
    \ 47 : "#8bffff",
    \ 48 : "#cd0000",
    \ 49 : "#cd008b",
    \ 50 : "#cd00cd",
    \ 51 : "#cd00ff",
    \ 52 : "#cd8b00",
    \ 53 : "#cd8b8b",
    \ 54 : "#cd8bcd",
    \ 55 : "#cd8bff",
    \ 56 : "#cdcd00",
    \ 57 : "#cdcd8b",
    \ 58 : "#cdcdcd",
    \ 59 : "#cdcdff",
    \ 60 : "#cdff00",
    \ 61 : "#cdff8b",
    \ 62 : "#cdffcd",
    \ 63 : "#cdffff",
    \ 64 : "#ff0000",
    \ 65 : "#ff008b",
    \ 66 : "#ff00cd",
    \ 67 : "#ff00ff",
    \ 68 : "#ff8b00",
    \ 69 : "#ff8b8b",
    \ 70 : "#ff8bcd",
    \ 71 : "#ff8bff",
    \ 72 : "#ffcd00",
    \ 73 : "#ffcd8b",
    \ 74 : "#ffcdcd",
    \ 75 : "#ffcdff",
    \ 76 : "#ffff00",
    \ 77 : "#ffff8b",
    \ 78 : "#ffffcd",
    \ 79 : "#ffffff",
    \ 80 : "#2e2e2e",
    \ 81 : "#5c5c5c",
    \ 82 : "#737373",
    \ 83 : "#8b8b8b",
    \ 84 : "#a2a2a2",
    \ 85 : "#b9b9b9",
    \ 86 : "#d0d0d0",
    \ 87 : "#e7e7e7",
\ }

function! s:ReadRgbTxt()
    let lines = readfile($VIMRUNTIME . "/rgb.txt")

    let colors = {}
    for line in lines
        let pieces = matchlist(line, '\v^\s*(\d+)\s+(\d+)\s+(\d+)\s+((\w| )+)')
        if !empty(pieces)
            let [r, g, b, name] = pieces[1:4]
            let colors[tolower(name)] = printf("#%02x%02x%02x", r, g, b)
        endif
    endfor

    return colors
endfunction

call extend(s:color_names, s:ReadRgbTxt())

" }}}

let &cpo = s:save_cpo
