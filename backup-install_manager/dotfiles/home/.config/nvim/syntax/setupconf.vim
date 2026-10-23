" ============================================================
" SETUPCONF
" Підсвічування конфігураційних файлів *.conf
" ============================================================

if exists("b:current_syntax")
    finish
endif

" ------------------------------------------------------------
" COMMENTS
" ------------------------------------------------------------

syntax match setupConfComment "^#.*$"

" ------------------------------------------------------------
" SECTIONS
" ------------------------------------------------------------

syntax match setupConfSection
            \ "^\s*\[[^]]\+\]\s*$"

" ------------------------------------------------------------
" KEYS
" ------------------------------------------------------------

syntax match setupConfKey
            \ "^\s*\zs[A-Za-z_][A-Za-z0-9_.-]*\ze\s*="

" ------------------------------------------------------------
" OPERATORS
" ------------------------------------------------------------

syntax match setupConfOperator "="
syntax match setupConfPipe "|"

" ------------------------------------------------------------
" STRINGS
" ------------------------------------------------------------

syntax region setupConfString
            \ start=+"+
            \ skip=+\\"+
            \ end=+"+

syntax region setupConfString
            \ start=+'+
            \ skip=+\\'+
            \ end=+'+

" ------------------------------------------------------------
" BOOLEAN
" ------------------------------------------------------------

syntax keyword setupConfBoolean
            \ true
            \ false
            \ yes
            \ no
            \ on
            \ off

" ------------------------------------------------------------
" NUMBERS
" ------------------------------------------------------------

syntax match setupConfNumber
            \ "\<\d\+\>"

" ------------------------------------------------------------
" PATHS
" ------------------------------------------------------------

syntax match setupConfPath
            \ "\%(\~\/\|\/\|\.\.\/\|\.\/\)[A-Za-z0-9_./@%+,:=-]*"

" ------------------------------------------------------------
" VALUES AFTER =
" ------------------------------------------------------------

syntax match setupConfValue
            \ "\%(^\s*[A-Za-z_][A-Za-z0-9_.-]*\s*=\s*\)\@<=.*$"
            \ contains=setupConfString,setupConfBoolean,setupConfNumber,setupConfPath

" ------------------------------------------------------------
" PIPE FORMAT
" ------------------------------------------------------------

syntax match setupConfPipeName
            \ "^\s*\zs[A-Za-z0-9_.-]\+\ze\s*|"

syntax match setupConfPipeType
            \ "\%(^\s*[A-Za-z0-9_.-]\+\s*|\s*\)\@<=[A-Za-z0-9_.-]\+\ze\s*|"

" ------------------------------------------------------------
" HIGHLIGHT
" ------------------------------------------------------------

highlight default link setupConfComment Comment

" Секції — cyan
highlight setupConfSection
            \ guifg=#56B6C2
            \ ctermfg=cyan

" Ключі — темніший orange
highlight setupConfKey
            \ guifg=#C58A5A
            \ ctermfg=173

" Значення
highlight default link setupConfValue String

" = — світлий yellow
highlight setupConfOperator
            \ guifg=#F0DFAF
            \ ctermfg=223

" | — світлий yellow
highlight setupConfPipe
            \ guifg=#F0DFAF
            \ ctermfg=223

" Перша колонка pipe — темніший orange
highlight setupConfPipeName
            \ guifg=#C58A5A
            \ ctermfg=173

" Друга колонка pipe — темніший orange
highlight setupConfPipeType
            \ guifg=#C58A5A
            \ ctermfg=173

" Шлях — такий самий orange
highlight setupConfPath
            \ guifg=#C58A5A
            \ ctermfg=173

" Інше
highlight default link setupConfString String
highlight default link setupConfBoolean Boolean
highlight default link setupConfNumber Number

" ------------------------------------------------------------
" CURRENT SYNTAX
" ------------------------------------------------------------

let b:current_syntax = "setupconf"
