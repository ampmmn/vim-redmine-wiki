" vim: set ts=4 sts=4 sw=4 noet
" Wiki

scriptencoding utf-8

let s:saved_cpoptions=&cpoptions
set cpoptions&vim

" class:Wiki
" Wikiクラスの定義
let s:Wiki= {
\	'parent':{},
\	'url':'',
\	'proj_name':'',
\	'main_page_name':'',
\	'pages':{},
\	'is_readonly':0
\}

" Wikiクラスファクトリ関数
function! RedmineWiki#Wiki#createInstance(parent, url, proj_name)
	let newObj = deepcopy(s:Wiki)

	let newObj.parent    = a:parent
	let newObj.url       = a:url
	let newObj.proj_name = a:proj_name

	return newObj
endfunction

" 読み取り専用状態を設定する
function! s:Wiki.setReadOnly(is_readonly)
	let self.is_readonly = a:is_readonly
endfunction

" WikiのRedmineプロジェクト名(識別子)を取得
function! s:Wiki.getProjectName()
	return self.proj_name
endfunction

" APIキーをロードする
function! s:Wiki.loadAPIKey()
	if has_key(self, 'api_key') != 0
		return 1
	endif

	" ファイルからの取得を試みる
	let filepath = g:redminewiki_datadir . '/apikeys.json'
	if filereadable(filepath) != 0
		try
			let json = webapi#json#decode(join(readfile(filepath), "\n"))
		catch /.*/
			if !exists('*webapi#json#decode')
				throw 'RedmineWiki.vim requires webapi-vim'
			endif
		endtry

		if has_key(json, self.url) != 0
			let self.api_key = json[self.url]
			return 1
		endif
	else
		let json = {}
	endif

	" ファイルから取得できなかった場合はプロンプトから入力
	let api_key = input('Enter API key :')
	if api_key == ''
		return 0
	endif

	let json[self.url] = api_key
	let self.api_key = api_key

	" ファイルに保存
	call writefile(split(webapi#json#encode(json), "\n"), filepath)

	return 1

endfunction

" APIキーを削除する
function! s:Wiki.deleteAPIKey()
	let filepath = g:redminewiki_datadir . '/apikeys.json'
	if filereadable(filepath) != 0
		let json = webapi#json#decode(join(readfile(filepath), "\n"))

		if has_key(json, self.url) != 0
			call remove(json, self.url)
		endif
	else
		let json = {}
	endif

	" ファイルを更新
	call writefile(split(webapi#json#encode(json), "\n"), filepath)

	return 1
endfunction

" APIキーを取得する
function! s:Wiki.getAPIKey()
	return self.api_key
endfunction

" 指定ページに対するバッファが存在する場合にバッファをアクティブにする
function! s:Wiki.activatePageIfExists(pageName)
	if has_key(self.pages, a:pageName)
		let pageObj = self.pages[a:pageName]
		if pageObj.activate()
			return 1
		endif

		unlet self.pages[a:pageName]
	endif
	return 0
endfunction

" Wikiページオブジェクトの削除
function! s:Wiki.eraseWikiPageObject(pageName)
	if !has_key(self.pages, a:pageName)
		return 0
	endif

	unlet self.pages[a:pageName]
	return 1
endfunction

" Wikiリンクテキストから「表示文字列」部分を削除する
function! s:stripTitleText(pageName)
	let pageName = a:pageName
	if match(pageName, '|') != -1
		let pageName = substitute(pageName, '\v(.{-})\|.*$', '\1', '')
	endif

	" 使用できない文字を削除
	let pageName = substitute(pageName, '\v,|\.|\/|\?|;|\||\:', '', 'g')

	return pageName
endfunction

" 指定したWikiページを示すURL文字列を生成する
function! s:Wiki.getWikiURL(pageName, ext)
	let url = self.url . '/projects/' . self.getProjectName() . '/wiki'
	if a:pageName != ''
		let url .= '/' . webapi#http#encodeURI(a:pageName)
	endif

	if a:ext != ''
		if self.loadAPIKey() == 0
			throw 'API key is not yet set.'
		endif

		let url .= a:ext
		let url .= '?key=' . self.getAPIKey()
	endif
	return url
endfunction

" 指定したWikiページを取得する
function! s:Wiki.getPageContent(pageName)

	let response = webapi#http#get(self.getWikiURL(a:pageName, '.json'))
	try
		if response.status == 401
			call self.deleteAPIKey()
			call s:echoErr('Unauthorized : Bad API key.')
			return {}
		elseif response.status == 404
			" 404の場合はページがない(新規作成する)
			return {}
		elseif response.status != 200
			call s:echoErr('An error occurred. HTTP status is ' . response.status . '.')
			return {}
		endif

		let json = webapi#json#decode(response["content"])
		return json.wiki_page
	catch /.*/
		return {}
	endtry
endfunction

" 指定したWikiページを開く
function! s:Wiki.openPage(pageName)

	" バー文字があったら以降を除去
	let pageName = s:stripTitleText(a:pageName)

	" 「:」があったら別プロジェクトのWikiページ
	if match(pageName, ':') != -1
		let proj_name = substitute(pageName, '\v(.*):.*$', '\1', '')
		let pageName  = substitute(pageName, '\v.*:(.*)$', '\1', '')

		let wikiMap = self.parent
		let newWikiObj = wikiMap.createWiki(self.url, proj_name)
		return newWikiObj.openPage(pageName)
	endif

	" 既存ページの場合は該当バッファをアクティブにする
	if self.activatePageIfExists(pageName) != 0
		return 1
	endif

	" ページの内容を取得
	let wiki_page = self.getPageContent(pageName)
	if has_key(wiki_page, 'text') == 0
		return 0
	endif

	let newPageObj = RedmineWiki#WikiPage#createInstance(self, pageName)
	if has_key(wiki_page, 'parent')
		let newPageObj.parentPageName = wiki_page.parent.title
	endif

	" バッファを作成
	call newPageObj.makeBuffer(wiki_page.text)
	let self.pages[pageName] = newPageObj

	" 取得時のページバージョンを保存しておく(更新時の衝突チェックで使う)
	let newPageObj.version = wiki_page.version

	if self.is_readonly != 0
		call newPageObj.setReadOnly()
	endif


	return 1
endfunction

" 指定した名前のWikiページを新規作成する
function! s:Wiki.createPage(parentPageName, pageName)
	" Limitation : 親ページ名を指定しての作成には対応していない

	let pageName = s:stripTitleText(a:pageName)

	" 「:」があったら別プロジェクトのWikiページ
	if match(pageName, ':') != -1
		let proj_name = substitute(pageName, '\v(.*):.*$', '\1', '')
		let pageName  = substitute(pageName, '\v.*:(.*)$', '\1', '')

		let wikiMap = self.parent
		let newWikiObj = wikiMap.createWiki(self.url, proj_name)
	endif

	" もし、ページがすでに存在する場合は該当バッファをアクティブにして処理を終了する
	if self.activatePageIfExists(pageName) != 0
		return 1
	endif

	let newPageObj = RedmineWiki#WikiPage#createInstance(self, pageName)

	" FIXME: REST APIでの親ページ指定が現状できないのでここでは親ページ名を持たないでおく
	let newPageObj.parentPageName = ""
	" let newPageObj.parentPageName = a:parentPageName

	" バッファ作成
	call newPageObj.makeBuffer('h1. ' . pageName)
	let self.pages[pageName] = newPageObj

	return 1
endfunction

" Wikiのメインページ名を取得する
function! s:Wiki.getMainPageName()
	if self.main_page_name != ''
		return self.main_page_name
	endif

	let url = self.getWikiURL('', '.json')
	try
		let response = webapi#http#get(url)
		let self.main_page_name = webapi#json#decode(response['content']).wiki_page.title
		return self.main_page_name
	catch /.*/
		let self.main_page_name = 'Wiki'
		return self.main_page_name
	endtry
endfunction

" メインページを開く
function! s:Wiki.openMainPage()
	return self.openPage(self.getMainPageName())
endfunction

" ページ名降順でソートするための関数
function! s:pageCompare(page1, page2)
	return a:page1.title < a:page2.title
endfunction


" 名前順一覧に表示するバッファの内容を生成する
function! s:Wiki.makeIndexContent()
	let pages = self.getIndex()

	let pages_to_list = []

	for page in pages
		if has_key(page, 'parent') == 0
			call add(pages_to_list, copy(page))
			let pages_to_list[-1].depth = 0
		else
			for page2 in pages
				if page2.title != page.parent.title
					continue
				endif

				if has_key(page2, 'children') == 0
					let page2.children = []
				endif
				call add(page2.children, page)
			endfor
		endif
	endfor

	call sort(pages_to_list, 's:pageCompare')

	let pageText = ''
	while !empty(pages_to_list)
		let page = pages_to_list[-1]
		let depth = page.depth
		call remove(pages_to_list, -1)

		let pageText .= repeat(' ', depth * 2) . '[[' . page.title . ']]' . "\n"

		if has_key(page, 'children')
			call sort(page.children, 's:pageCompare')
			for page2 in page.children
				call add(pages_to_list, copy(page2))
				let pages_to_list[-1].depth = depth+1
			endfor
		endif
	endwhile

	return pageText
endfunction

" 名前順一覧を開く
function! s:Wiki.openIndex()
	let bufname = '__Index'

	" ページに対するバッファが既存の場合はそれをアクティブにする
	if self.activatePageIfExists(bufname) != 0
	 return 1
	endif


	" バッファ作成
	let newPageObj = RedmineWiki#WikiPage#createInstance(self, bufname)
	call newPageObj.makeBuffer(self.makeIndexContent())

	let self.pages[bufname] = newPageObj

	" バッファは読み取り専用にする
	call newPageObj.setReadOnly()

	return 1
endfunction

" 日付順一覧に表示するバッファの内容を生成する
function! s:Wiki.makeDateIndexContent()
	let pages = self.getIndex()

	let pagesByDate = {}
	for page in pages
		let date_str = substitute(page.updated_on, '\v(\d\d\d\d-\d\d-\d\d).*$', '\1', '')
		if has_key(pagesByDate, date_str) != 0
			call add(pagesByDate[date_str], page)
		else
			let pagesByDate[date_str] = [ page ]
		endif
	endfor

	let dates = keys(pagesByDate)
	call reverse(sort(dates))

	let pageText = ''
	for key in dates
		let page_list = pagesByDate[key]

		let pageText .= key . "\n"

		call reverse(sort(page_list, 's:pageCompare'))
		for page in page_list
			let pageText .= "  [[" . page.title . "]]\n"
		endfor
	endfor

	return pageText
endfunction

" 日付順一覧を開く
function! s:Wiki.openDateIndex()

	let bufname = '__DateIndex'

	" ページに対するバッファが既存の場合はそれをアクティブにする
	if self.activatePageIfExists(bufname) != 0
	 return 1
	endif

	" バッファを作成
	let newPageObj = RedmineWiki#WikiPage#createInstance(self, bufname)
	call newPageObj.makeBuffer(self.makeDateIndexContent())

	let self.pages[bufname] = newPageObj

	" バッファは読み取り専用にする
	call newPageObj.setReadOnly()

	return 1
endfunction

" ページ名の一覧をサイトから取得する
function! s:Wiki.getIndex()
	try
		let response = webapi#http#get(self.getWikiURL('index', '.json'))
		return webapi#json#decode(response['content'])['wiki_pages']
	catch /.*/
		return []
	endtry
endfunction

" エラーメッセージをハイライト出力する
function! s:echoErr(msg)
	echohl ErrorMsg | echo a:msg | echohl
	return 0
endfunction

let &cpoptions=s:saved_cpoptions
unlet s:saved_cpoptions
