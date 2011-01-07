" Rethrow support for Vim scripts.
" Last Change: 2011 Jan 7
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

let s:save_cpo = &cpo
set cpo&vim

let s:rethrow_pattern = '\v\<SNR\>\d+_Rethrow>'

function! rethrow#Rethrow()
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

function! rethrow#Throwpoint()
    if v:throwpoint =~# s:rethrow_pattern
        return s:rethrow_throwpoint
    else
        return v:throwpoint
    endif
endfunction

let &cpo = s:save_cpo
