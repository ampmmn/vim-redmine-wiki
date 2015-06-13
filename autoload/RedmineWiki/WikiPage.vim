" vim: set ts=4 sts=4 sw=4 noet
" WikiMap

scriptencoding utf-8

" ToDo: 履歴関連の機能を実装する

let s:saved_cpoptions=&cpoptions
set cpoptions&vim

let s:pageHeader = [
\'[MainPage] [Index] [DateIndex] [Reload] [DeletePage] [OpenBrowser]',
\'--------------------------------------------------------------------------------'
\]

if exists(':OpenBrowser') != 2
	let s:pageHeader[0] = substitute(s:pageHeader[0], '\v \[OpenBrowser\]', '', '')
endif

" class:WikiPage
" WikiPageクラスの定義
let s:WikiPage = {
\ 'wikiObj' : {},
\ 'parentPageName' : '',
\ 'pageName' : '',
\ 'version' : '',
\ 'bufnr' : -1
\}

" WikiPageクラス生成メソッド
function! RedmineWiki#WikiPage#createInstance(wikiObj, pageName)
	let newObj = deepcopy(s:WikiPage)

	let newObj.wikiObj = a:wikiObj
	let newObj.pageName = a:pageName

	if a:pageName == ''
		let newObj.pageName = 'Wiki'
	endif
	" ページ名として利用できない文字は削除
	let newObj.pageName = substitute(newObj.pageName, '\v[[,./?;:|]', '', 'g')
	let newObj.bufnr = -1

	return newObj
endfunction

" ページに関連付けられたバッファをアクティブにする
function! s:WikiPage.activate()
	let nr = self.bufnr
	if bufexists(nr) == 0 || bufloaded(nr) == 0
		return 0
	endif

	try
		silent execute nr 'buffer'
		return 1
	catch /.*/
		return 0
	endtry
endfunction

" 指定されたテキストでバッファの内容を初期化する
function! s:WikiPage.initBufferContent(pageText)
	setlocal noreadonly modifiable noai noswapfile

	" 一時的にundo/redo機能を無効化し、変更内容がundoツリーに残らないようにする
	let org_ul = &undolevels
	let &undolevels = -1

	try
		normal! gg"_dG

		" Wikiページの内容を貼り付ける
		execute "normal! i" . substitute(a:pageText, '\v\r\n', '\n', 'g')

		" 1行目に親ページ名と現在のページ名を表示する
		let pagePath = ''
		if self.parentPageName != ''
			let pagePath = '[[' . self.parentPageName . ']]' >> '
		endif
		let pagePath .= self.pageName
		call append(0, pagePath)

		" ヘッダ行を追加
		call append(1, s:pageHeader)

		" ページコンテンツ先頭にカーソルを設定
		execute 'normal!' (len(s:pageHeader)+2).'G^z.'
	finally
		let &undolevels = org_ul
		set nomodified
	endtry
endfunction

" 与えられたWikiコンテンツをもとにVimバッファを作成する
function! s:WikiPage.makeBuffer(pageText)
	if bufexists(self.bufnr) != 0
		return 0
	endif

	let proj_name = self.wikiObj.getProjectName()

	silent execute 'edit ++enc=utf-8 ++ff=dos ' proj_name '::' substitute(self.pageName, ' ', '\\ ', 'g')
	setlocal ft=redminewiki
	let self.bufnr = bufnr('%')

	call self.initBufferContent(a:pageText)

	augroup RedmineWikiEdit
		execute 'autocmd! BufEnter'    substitute(expand('%'), ' ', '\\ ', 'g') 'call b:wikiPageObj.enterBuffer()'
		execute 'autocmd! BufWriteCmd' substitute(expand('%'), ' ', '\\ ', 'g') 'call b:wikiPageObj.save()'
		execute 'autocmd! BufDelete'   substitute(expand('%'), ' ', '\\ ', 'g') 'call s:deleteBuffer()'
	augroup END

	let b:wikiPageObj = self

	" バッファ固有のマッピングを設定する
	call self.enterBuffer()

	return 1

endfunction

function! s:WikiPage.enterBuffer()
	nnoremap <silent><buffer> <CR> :call <SID>openWikiLink()<cr>
	nnoremap <silent><buffer> gb :<c-u>RedmineWikiBookmark<cr>
	nnoremap <silent><buffer> gx :call b:wikiPageObj.openBrowser()<cr>
endfunction

" バッファを読み取り専用にする
function! s:WikiPage.setReadOnly()
	if bufexists(self.bufnr) == 0
		return 0
	endif

	if self.bufnr != bufnr('%')
		silent execute self.bufnr 'buffer'
	endif

	setlocal readonly nomodifiable

	return 1
endfunction

" バッファは読み取り専用か?
function! s:WikiPage.isReadOnly()

	if bufexists(self.bufnr) == 0
		return 0
	endif

	if self.bufnr != bufnr('%')
		silent execute self.bufnr 'buffer'
	endif

	return &modifiable == 0
endfunction

" ページの保存を行う
function! s:WikiPage.save()
	call self.activate()

	" コンテンツ開始行を検索
	" 区切り文字(-----)の次行をコンテンツ開始行とする
	let line_head = 1
	while line_head <= 5
		if match(getline(line_head), '------') != -1
			let line_head = line_head + 1
			break
		endif
		let line_head = line_head + 1
	endwhile

	if line_head > 5
		" 区切り文字が削除された?
		echo 'Divider line is missing.'
		return
	endif

	let page_text = ''

	let line_count = line('$')
	let i = line_head
	while i <= line_count
		if i != line_head
			let page_text .= "\n"
		endif
		let page_text .= getline(i)
		let i += 1
	endwhile

	let page_text = webapi#html#encodeEntityReference(page_text)
	" なぜかRedmineのほうでは&nbsp;を解釈してくれないようなので
	" スペースに戻す
	let page_text = substitute(page_text, '\v\&nbsp;', ' ', 'g')

	let wikiObj = self.wikiObj
	let url = wikiObj.getWikiURL(self.pageName, '.xml')

	"
	let xml  = '<?xml version="1.0" encoding="UTF-8"?><wiki_page>'
	let xml .= '<text>' . page_text . '</text>'

	" FIXME: 現状RedmineのWiki APIは作成時の親ページ指定をサポートしていない
	" (2.6.5時点)
	" このため、↓のブロックは意味ない
	if self.parentPageName != ''
		let xml .= '<parent title="' . self.parentPageName . '"/>'
	endif

	let xml .= '<version>' . self.version . '</version>'
	let xml .= '<comments></comments>'
	let xml .= '</wiki_page>'

	let response = webapi#http#post(url, iconv(xml, &encoding, 'utf-8'), 
	\                               {'Content-Type' : 'application/xml'}, 'PUT')

	let sts = response.status
	if sts == 409
		return s:echoErr('Conflict : ' . self.pageName . ' is already updated.')
	elseif sts != 200 && sts != 201
		return s:echoErr('Unable to create/update wiki_page : ' . self.pageName)
	endif

	" 
	call self.reload()

	echo 'wiki_page : ' self.pageName . (sts == 200 ? ' updated.' : ' created.')

	return 1

endfunction

" ページの再読み込みを行う
function! s:WikiPage.reload()

	if self.pageName == '__Index'
		call self.initBufferContent(self.wikiObj.makeIndexContent())
		call self.setReadOnly()
	elseif self.pageName == '__DateIndex'
		call self.initBufferContent(self.wikiObj.makeDateIndexContent())
		call self.setReadOnly()
	else
		let wikiObj = self.wikiObj
		let wiki_page = wikiObj.getPageContent(self.pageName)
		if has_key(wiki_page, 'text') == 0
			return
		endif

		call self.initBufferContent(wiki_page.text)

		" ページバージョンを更新する
		let self.version = wiki_page.version
	endif

	" 変更済みフラグをクリアする
	set nomodified
endfunction

" ページの削除を行う
function! s:WikiPage.deletePage()
	if self.activate() == 0
		return
	endif

	if self.isReadOnly() != 0
		return 
	endif

	let yesno = input('Are you sure you want to delete ' . self.pageName . '? (y/N):')
	if yesno != 'y'
		return
	endif

	let wikiObj = self.wikiObj

	" 
	let url = wikiObj.getWikiURL(self.pageName, '.json')
	let xml = '<?xml version="1.0" encoding="UTF-8"?><wiki_page></wiki_page>'

	let response = webapi#http#post(url, xml, {'Content-Type:' : 'application/xml'}, 'DELETE')

	let sts = response.status
	if sts != 200
		return s:echoErr('Unable to delete : ' . self.pageName)
	endif

	silent bdelete!

	let parentPageName = self.parentPageName
	let pageName = self.pageName

	call wikiObj.eraseWikiPageObject(pageName)
	call wikiObj.createPage(parentPageName, pageName)

	echo self.pageName . ' was deleted.'
endfunction

function! s:getCurPosText(text_obj)
	let org_a = @a
	let @a = ''

	execute 'normal! "ay' . a:text_obj

	let text=@a
	let @a=org_a

	return text
endfunction

" バッファが削除される際に呼ばれる処理
function! s:deleteBuffer()
	" バッファ作成時に登録したautocmdを削除する
	augroup RedmineWikiEdit
		execute 'autocmd! BufEnter' substitute(expand('%'), ' ', '\\ ', 'g')
		execute 'autocmd! BufWriteCmd' substitute(expand('%'), ' ', '\\ ', 'g')
		execute 'autocmd! BufDelete' substitute(expand('%'), ' ', '\\ ', 'g')
	augroup END
endfunction

" ヘッダ行で<CR>を押した際の処理を記述する関数
function! s:WikiPage.openHeaderLink()

	let wikiObj = self.wikiObj

	let itemName = s:getCurPosText('i[')
	if itemName == 'MainPage'
		return wikiObj.openMainPage()
	elseif itemName == 'Index'
		return wikiObj.openIndex()
	elseif itemName == 'DateIndex'
		return wikiObj.openDateIndex()
	elseif itemName == 'Reload'
		return self.reload()
	elseif itemName == 'DeletePage'
		return self.deletePage()
	elseif itemName == 'OpenBrowser'
		return self.openBrowser()
	endif

	return 0
endfunction

" ページ上で<CR>を押した際に呼ぶ関数
" カーソル位置がリンク上にあったら、リンク先へ飛ぶ
function! s:openWikiLink()


	if exists('b:wikiPageObj') == 0
		return
	endif

	" ヘッダ行をクリックした場合はメニュー項目に応じた処理を実行
	if getline(".") == s:pageHeader[0]
		return b:wikiPageObj.openHeaderLink()
	endif

	" 現在の行にあるリンクの数を数える
	let line = getline('.')
	let links = []
	while match(line, '\v\[\[.{-}\]\]') >= 0
		let link = substitute(line, '\v.{-}\[\[(.{-})\]\].*', '\1', '')
		let line = substitute(line, '\v\[\[.{-}\]\]', '', '')
		call add(links, link)
	endwhile

	let link_count = len(links)
	if link_count == 0
		return
	endif

	" 現在行にリンクが一つだけの場合はそれを開く。
	" 複数存在する場合は、現在位置にあるテキストを拾って開く。
	if link_count == 1
		let wikiObj = b:wikiPageObj.wikiObj
		if wikiObj.openPage(links[0]) != 0
			return 1
		endif
		return wikiObj.createPage(b:wikiPageObj.pageName, links[0])
	endif

	let newPageName = s:getCurPosText('i[')

	" 抽出した文字列が[ ... ]で囲われていたらカッコを除去する
	if match(newPageName, '\v^\[.*\]$') >= 0
		let newPageName = substitute(newPageName, '\v^\[(.*)\]$', '\1', '')
	endif

	if newPageName != ''
		let wikiObj = b:wikiPageObj.wikiObj
		if wikiObj.openPage(newPageName) == 0
			return wikiObj.createPage(b:wikiPageObj.pageName, newPageName)
		endif
	endif
endfunction

function! s:WikiPage.openBrowser()

	let pageName = b:wikiPageObj.pageName
	if pageName == '__Index'
		let pageName = 'index'
	elseif pageName == '__DateIndex'
		let pageName = 'date_index'
	endif

	let wikiObj = b:wikiPageObj.wikiObj
	if exists(':OpenBrowser') == 2
		execute 'silent OpenBrowser' wikiObj.getWikiURL(pageName, '')
		return 1
	endif
	return 0
endfunction

" エラーメッセージをハイライト出力する
function! s:echoErr(msg)
	echohl ErrorMsg | echo a:msg | echohl
	return 0
endfunction

let &cpoptions=s:saved_cpoptions
unlet s:saved_cpoptions

