" vim:set ts=4 sts=4 sw=4 noet
" RedmineWiki.vim 0.0.1

if exists('loaded_redminewiki') || &cp || version < 700
	finish
endif

command! -nargs=0 RedmineWikiBookmark call RedmineWiki#WikiMap#ShowBookmark()
