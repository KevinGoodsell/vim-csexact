" Utilities for CSExact.
" Last Change: 2011 November 27
" Maintainer:  Kevin Goodsell <kevin-opensource@omegacrash.net>
" License:     GPL (see below)

" {{{ COPYRIGHT & LICENSE
"
" Copyright 2011 Kevin Goodsell
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

let s:save_cpo = &cpo
set cpo&vim

" {{{ UTILITY FUNCTIONS

" csexat#TermDetails attempts to determine information about the underlying
" terminal and returns a dictionary of the information it finds. This is used
" inside CSExact, but can also be useful in a vimrc file to decide how to set
" options like g:csexact_cursor_reset. Pass in a "true" value to cause it to
" use the value of g:csexact_term_override. Otherwise this is ignored and only
" &term is used.
"
" If the detection used here isn't working for your configuration you can force
" this to see the terminal and multiplexer of your choice by setting &term or
" g:csexact_term_override to <multiplexer>.<host_term>.
"
" The resulting dictionary may include these fields:
"
"   result.term:        The terminal (screen, tmux, xterm, etc.)
"   result.multiplexer: The terminal multiplexer, if available (screen or tmux)
"   result.host_term:   The underlying terminal, if it can be determined
"
" 'term' is the "top" terminal, and will be the same as 'multiplexer' or
" 'host_term', depending on whether a multiplexer is running or not.
"
" Any field except 'term' might be missing in the result if it can't be
" determined.
function! csexact#TermDetails(...)
    if a:0 == 1
        let use_override = a:1
    else
        let use_override = 0
    endif

    if use_override
        let term = get(g:, "csexact_term_override", &term)
    else
        let term = &term
    endif

    let result = {}

    " In screen or tmux, term typically starts with "screen". We also recognize
    " "tmux" as an indication that the multiplexer is tmux.
    if term =~# '\v^(screen|tmux)'
        if term =~# '\v^tmux' || exists("$TMUX")
            let result.multiplexer = "tmux"
        else
            let result.multiplexer = "screen"
        endif

        let result.term = result.multiplexer

        " Figure out host term.

        " Maybe term is multiplexer.host-term.
        if term =~# '\v^(screen|tmux)\.'
            let result.host_term = matchstr(term, '\v^(screen|tmux)\.\zs.*')
        " Maybe XTERM_VERSION is set.
        elseif !empty($XTERM_VERSION)
            let result.host_term = "xterm"
        " Maybe COLORTERM is set.
        elseif !empty($COLORTERM)
            let result.host_term = $COLORTERM
        endif
    else
        let result.term = term
        let result.host_term = term
    endif

    return result
endfunction

" }}}

let &cpo = s:save_cpo
