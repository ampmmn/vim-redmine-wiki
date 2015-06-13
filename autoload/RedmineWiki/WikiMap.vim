" vim: set ts=4 sts=4 sw=4 noet
" WikiMap

scriptencoding utf-8

let s:saved_cpoptions=&cpoptions
set cpoptions&vim

if !exists('g:redminewiki_datadir')
	let g:redminewiki_datadir = expand(split(&runtimepath, ',')[0] . '/redminewiki')
endif

let s:bookmark_template = [
\"h1. RedmineWiki.vim Bookmark Page",
\"",
\"h2. How To Use",
\"",
\"You can write URL(s) point to redmine wiki you want to browse/edit in this file.",
\"(URL must point to the top page of a redmine project.)",
\"",
\"You can use this file to list redmine sites where you often browse.",
\"",
\"Move cursor to URL, press enter key, and you'll be able to browse/edit.",
\"",
\"h2. Formatting",
\"",
\"  <URL> [ Tab <PageName> ] [ Tab ReadOnly ]",
\"",
\"* Each columns are separated with tab.",
\"* <PageName> will be the start page of wiki of the redmine project ",
\"  if it is not present.",
\"* Wiki will be opened as readonly if \"ReadOnly\" is present.",
\"* When you specify \"ReadOnly\", <PageName> must be present.",
\"",
\"The following is an example bookmark.",
\"--------------------------------------------------------------------------------",
\"",
\"Project foo",
\"\thttp://localhost/redmine/projects/foot\tWiki",
\"Project bar",
\"\thttp://localhost/redmine/projects/bar\tWiki\tReadOnly",
\"OtherRedmine",
\"\thttps://otherhost/projects/baz",
\]

" class:WikiMap
" WikiMapクラスの定義
let s:WikiMap = { 'wikis':{} }

function! s:WikiMap.createWiki(url, proj_name)
	if has_key(self.wikis, a:proj_name) != 0
		return self.wikis[a:proj_name]
	endif

	let newWikiObj = RedmineWiki#Wiki#createInstance(self, a:url, a:proj_name)
	let self.wikis[newWikiObj.getProjectName()] = newWikiObj

	return newWikiObj
endfunction

function! RedmineWiki#WikiMap#ShowBookmark()
	if isdirectory(g:redminewiki_datadir) == 0 &&
	\  mkdir(g:redminewiki_datadir) == 0
		return s:echoErr('Unable to create data directory.')
	endif

	let bookmark_path = g:redminewiki_datadir . '/bookmark.list'

	if filereadable(bookmark_path) == 0
		if writefile(s:bookmark_template, bookmark_path) != 0
			return s:echoErr('Unable to create bookmark page.')
		endif
	endif

	" ブックマークページを表示
	if bufexists(bookmark_path) != 0
		execute bufnr(bookmark_path) "buffer"
		return
	endif

	" ブックマークページ(バッファ)が存在しない場合は新規作成する
	execute "edit" bookmark_path

	let b:wikiObjMap = deepcopy(s:WikiMap)

	" ToDo: autocmd設定

	call s:enterBuffer()
endfunction

function! s:enterBuffer()
	" ブックマークページ上で有効なキーマッピングを設定する
	nnoremap <silent><buffer> <CR> :<c-u>call <SID>openBookmarkItem('.')<cr>
endfunction

" 指定したサイトを開く
function! s:openBookmarkItem(line)

	if exists('b:wikiObjMap') == 0
		return 0
	endif

	" 指定行の情報を読み取り、アクセス先サイトの情報を抽出する
	let line = getline(a:line)
	if line !~# '\v^\s*https?://.+(\t\+.*)?$'
		return 0
	endif

	let url = substitute(line, '\v^\s*(https?://[^\t]+).*$', '\1', '')
	let pageName = ''
	if match(line, '\v\s*[^\t]+\t+[^\t]+') != -1
		let pageName = substitute(line, '\v^\s*[^\t]+\t+([^\t]+).*$', '\1', '')
	endif
	let is_readonly = (match(line, "\tReadOnly") != -1)

	" URL末尾が「/」で終わっていたら除去する
	if match(url, '\v.*/$') != -1
		let url = substitute(url, '/$', '', '')
	endif

	let site_url = substitute(url, '\v/projects/.+$', '', '')
	let proj_name= substitute(url, '\v^.*/', '', '')

	try
		let wikiMap = b:wikiObjMap
		let wikiObj = wikiMap.createWiki(site_url, proj_name)
		call wikiObj.setReadOnly(is_readonly)

		if pageName != ''
			call wikiObj.openPage(pageName)
		else
			call wikiObj.openMainPage()
		endif
		return 1
	catch /.*/
		return s:echoErr(v:exception)
	endtry
endfunction

" エラーメッセージをハイライト出力する
function! s:echoErr(msg)
	echohl ErrorMsg | echo a:msg | echohl
	return 0
endfunction

let &cpoptions=s:saved_cpoptions
unlet s:saved_cpoptions
