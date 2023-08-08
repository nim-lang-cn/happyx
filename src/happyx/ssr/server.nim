## # Server 🔨
## 
## Provides a Server object that encapsulates the server's address, port, and logger.
## Developers can customize the logger's format using the built-in newConsoleLogger function.
## HappyX provides two options for handling HTTP requests: httpx, microasynchttpserver and asynchttpserver.
## 
## 
## To enable httpx just compile with `-d:httpx` or `-d:happyxHttpx`.
## To enable MicroAsyncHttpServer just compile with `-d:micro` or `-d:happyxMicro`.
## To enable HttpBeast just compile with `-d:beast` or `-d:happyxBeast`
## 
## To enable debugging just compile with `-d:happyxDebug`.
## 
## ## Queries ❔
## In any request you can get queries.
## 
## Just use `query~name` to get any query param. By default returns `""`
## 
## If you want to use [arrays in query](https://github.com/HapticX/happyx/issues/101) just use
## `queryArr~name` to get any array query param.
## 
## ## WebSockets 🍍
## In any request you can get connected websocket clients.
## Just use `wsConnections` that type is `seq[WebSocket]`
## 
## In any websocket route you can use `wsClient` for working with current websocket client.
## `wsClient` type is `WebSocket`.
## 
## 
## ## Static directories 🍍
## To declare static directory you just should mark it as static directory 🙂
## 
## .. code-block:: nim
##    serve(...):
##      # Users can get all files in /myDirectory via
##      # http://.../myDirectory/path/to/file
##      staticDir "myDirectory"
## 
## ### Custom static directory ⚙
## To declare custom path for static dir just use this
## 
## .. code-block:: nim
##    serve(...):
##      # Users can get all files in /myDirectory via
##      # http://.../customPath/path/to/file
##      staticDir "/customPath" -> "myDirectory"
## 
## > Note: here you can't use path params
## 

import
  # Stdlib
  std/asyncdispatch,
  std/strformat,
  std/asyncfile,
  std/segfaults,
  std/mimetypes,
  std/strutils,
  std/terminal,
  std/strtabs,
  std/logging,
  std/cookies,
  std/macros,
  std/tables,
  std/colors,
  std/json,
  std/os,
  std/exitprocs,
  packages/docutils/rst,
  packages/docutils/rstgen,
  # Deps
  regex,
  # HappyX
  ./cors,
  ../spa/[tag, renderer, translatable],
  ../core/[exceptions, constants],
  ../private/[macro_utils],
  ../routing/[routing, mounting],
  ../sugar/sgr

export
  strutils,
  strtabs,
  strformat,
  asyncdispatch,
  asyncfile,
  logging,
  terminal,
  cookies,
  colors,
  regex,
  json,
  os


when enableHttpx:
  import
    options,
    httpx
  export
    options,
    httpx
elif enableHttpBeast:
  import httpbeast, asyncnet
  export httpbeast, asyncnet
elif enableMicro:
  import microasynchttpserver, asynchttpserver
  export microasynchttpserver, asynchttpserver
else:
  import asynchttpserver
  export asynchttpserver


when enableHttpBeast:
  import websocket
  export websocket
else:
  import websocketx
  export websocketx


when enableApiDoc:
  import
    nimja,
    ../private/api_doc_template


type
  Server* = object
    address*: string
    port*: int
    logger*: Logger
    when enableHttpx:
      instance*: Settings
    elif enableHttpBeast:
      instance*: Settings
    elif enableMicro:
      instance*: MicroAsyncHttpServer
    else:
      instance*: AsyncHttpServer
    components: TableRef[string, BaseComponent]
  ModelBase* = object of RootObj


when enableApiDoc:
  type
    ApiDocPathParamObject* = object
      name*: string
      paramType*: string
      defaultVal*: string
      optional*: bool
      mutable*: bool
    ApiDocObject* = object
      description*: string
      httpMethod*: string
      path*: string
      pathParams*: seq[ApiDocPathParamObject]
    
  proc newApiDocObject*(httpMethod, description, path: string, pathParams: seq[ApiDocPathParamObject]): ApiDocObject =
    ApiDocObject(httpMethod: httpMethod, description: description, path: path, pathParams: pathParams)
  proc newApiDocPathParamObject*(name, paramType, defaultVal: string, optional, mutable: bool): ApiDocPathParamObject =
    ApiDocPathParamObject(
      name: name, paramType: paramType, defaultVal: defaultVal,
      optional: optional, mutable: mutable
    )



var
  pointerServer: ptr Server


proc ctrlCHook() {.noconv.} =
  quit(QuitSuccess)

proc onQuit() {.noconv.} =
  when int(enableHttpBeast) + int(enableHttpx) + int(enableMicro) == 0:
    when nim_2_0_0:
      if not pointerServer.isNil() and not pointerServer[].instance.isNil():
        pointerServer[].instance.close()
    else:
      try:
        pointerServer[].instance.close()
      except NilAccessDefect:
        discard


setControlCHook(ctrlCHook)
addExitProc(onQuit)


func fgColored*(text: string, clr: ForegroundColor): string {.inline.} =
  ## This function takes in a string of text and a ForegroundColor enum
  ## value and returns the same text with the specified color applied.
  ## 
  ## Arguments:
  ## - `text`: A string value representing the text to apply color to.
  ## - `clr`: A ForegroundColor enum value representing the color to apply to the text.
  ## 
  ## Return value:
  ## - The function returns a string value with the specified color applied to the input text.
  runnableExamples:
    echo fgColored("Hello, world!", fgRed)
  ansiForegroundColorCode(clr) & text & ansiResetCode


func fgStyled*(text: string, style: Style): string {.inline.} =
  ## This function takes in a string of text and a Style enum
  ## value and returns the same text with the specified style applied.
  ## 
  ## Arguments:
  ## - `text`: A string value representing the text to apply style to.
  ## - `clr`: A Style enum value representing the style to apply to the text.
  ## 
  ## Return value:
  ## - The function returns a string value with the specified style applied to the input text.
  runnableExamples:
    echo fgStyled("Hello, world!", styleBlink)
  ansiStyleCode(style) & text & ansiResetCode


proc newServer*(address: string = "127.0.0.1", port: int = 5000): Server =
  ## This procedure creates and returns a new instance of the `Server` object,
  ## which listens for incoming connections on the specified IP address and port.
  ## If no address is provided, it defaults to `127.0.0.1`,
  ## which is the local loopback address.
  ## If no port is provided, it defaults to `5000`.
  ## 
  ## Parameters:
  ## - `address` (optional): A string representing the IP address that the server should listen on.
  ##   Defaults to `"127.0.0.1"`.
  ## - `port` (optional): An integer representing the port number that the server should listen on.
  ## 
  ## Returns:
  ## - A new instance of the `Server` object.
  runnableExamples:
    var s = newServer()
    assert s.address == "127.0.0.1"
  result = Server(
    address: address,
    port: port,
    components: newTable[string, BaseComponent](),
    logger: newConsoleLogger(lvlInfo, fgColored("[$date at $time]:$levelname ", fgYellow)),
  )
  when enableHttpx or enableHttpBeast:
    result.instance = initSettings(Port(port), bindAddr=address, numThreads = numThreads)
  elif enableMicro:
    result.instance = newMicroAsyncHttpServer()
  else:
    result.instance = newAsyncHttpServer()
  pointerServer = addr result
  addHandler(result.logger)


proc parseQuery*(query: string): owned(StringTableRef) =
  ## Parses query and retrieves StringTableRef object
  runnableExamples:
    let
      query = "a=1000&b=8000&password=mystrongpass"
      parsedQuery = parseQuery(query)
    assert parsedQuery["a"] == "1000"
  result = newStringTable()
  for i in query.split('&'):
    let splitted = i.split('=')
    if splitted.len >= 2 and not splitted[0].endsWith("[]"):
      result[splitted[0]] = splitted[1]


proc parseQueryArrays*(query: string): TableRef[string, seq[string]] =
  ## Parses query and retrieves TableRef[string, seq[string]] object
  runnableExamples:
    import tables
    let
      query = "a[]=10&a[]=100&a[]=foo&a[]=bar"
      parsedQuery = parseQueryArrays(query)
    assert parsedQuery["a"] == @["10", "100", "foo", "bar"]
  result = newTable[string, seq[string]]()
  for i in query.split('&'):
    let splitted = i.split('=')
    if splitted.len >= 2 and splitted[0].endsWith("[]"):
      let key = splitted[0][0..^3]
      if result.hasKey(key):
        result[key].add(splitted[1])
      else:
        result[key] = @[splitted[1]]


template start*(server: Server): untyped =
  ## The `start` template starts the given server and listens for incoming connections.
  ## Parameters:
  ## - `server`: A `Server` instance that needs to be started.
  ## 
  ## Returns:
  ## - `untyped`: This template does not return any value.
  when enableDebug:
    info fmt"Server started at http://{server.address}:{server.port}"
  when not declared(handleRequest):
    proc handleRequest(req: Request) {.async.} =
      discard
  when enableHttpx or enableHttpBeast:
    run(handleRequest, `server`.instance)
  else:
    waitFor `server`.instance.serve(Port(`server`.port), handleRequest, `server`.address)


template answer*(
    req: Request,
    message: string,
    code: HttpCode = Http200,
    headers: HttpHeaders = newHttpHeaders([
      ("Content-Type", "text/plain; charset=utf-8")
    ])
) =
  ## Answers to the request
  ## 
  ## ⚠ `Low-level API` ⚠
  ## 
  ## Arguments:
  ##   `req: Request`: An instance of the Request type, representing the request that we are responding to.
  ##   `message: string`: The message that we want to include in the response body.
  ##   `code: HttpCode = Http200`: The HTTP status code that we want to send in the response.
  ##                               This argument is optional, with a default value of Http200 (OK).
  ## 
  ## Use this example instead
  ## 
  ## .. code-block::nim
  ##    get "/":
  ##      return "Hello, world!"
  ## 
  var h = headers
  h.addCORSHeaders()
  when enableHttpx or enableHttpBeast:
    var headersArr: seq[string] = @[]
    for key, value in h.pairs():
      headersArr.add(key & ':' & value)
    when declaredInScope(cookies):
      for cookie in cookies:
        headersArr.add(cookie)
    when declaredInScope(statusCode):
      req.send(statusCode.HttpCode, message, headersArr.join("\r\n"))
    else:
      req.send(code, message, headersArr.join("\r\n"))
  else:
    when declaredInScope(cookies):
      for cookie in cookies:
        let data = cookie.split(":", 1)
        h.add("Set-Cookie", data[1].strip())
    when declaredInScope(statusCode):
      await req.respond(statusCode.HttpCode, message, h)
    else:
      await req.respond(code, message, h)


when enableHttpBeast:
  proc send*(ws: AsyncWebSocket, data: string) {.async.} =
    await ws.sendText(data)


template answerJson*(req: Request, data: untyped, code: HttpCode = Http200,): untyped =
  ## Answers to request with json data
  ## 
  ## ⚠ `Low-level API` ⚠
  ## 
  ## Use this example instead
  ## 
  ## .. code-block::nim
  ##    var json = %*{"response": 1}
  ##    
  ##    get "/1":
  ##      # respond variable
  ##      return json
  ##    get "/2":
  ##      # respond JSON directly
  ##      return {"response": 1}
  ## 
  answer(req, $(%*`data`), code, newHttpHeaders([("Content-Type", "application/json; charset=utf-8")]))


template answerHtml*(req: Request, data: string | TagRef, code: HttpCode = Http200): untyped =
  ## Answers to request with HTML data
  ## 
  ## ⚠ `Low-level API` ⚠
  ## 
  ## Use this example instead:
  ##
  ## .. code-block::nim
  ##    var html = buildHtml:
  ##      tDiv:
  ##        "Hello, world!"
  ##    
  ##    get "/1":
  ##      # Respond HTML variable
  ##      return html
  ##    get "/2":
  ##      # Respond HTML directly
  ##      return buildHtml:
  ##        tDiv:
  ##          "Hello, world!"
  ## 
  when data is string:
    let d = data
  else:
    let d = $data
  answer(req, d, code, newHttpHeaders([("Content-Type", "text/html; charset=utf-8")]))


proc answerFile*(req: Request, filename: string,
                 code: HttpCode = Http200, asAttachment = false) {.async.} =
  ## Respond file to request.
  ## 
  ## ⚠ `Low-level API` ⚠
  ## 
  ## Use this example instead of this procedure
  ## 
  ## .. code-block::nim
  ##    get "/$filename":
  ##      return FileResponse("/publicFolder" / filename)
  ## 
  let
    splitted = filename.split('.')
    extension = if splitted.len > 1: splitted[^1] else: ""
    contentType = newMimetypes().getMimetype(extension)
  var f = openAsync(filename, fmRead)
  let content = await f.readAll()
  f.close()
  var headers = @[("Content-Type", fmt"{contentType}; charset=utf-8")]
  if asAttachment:
    headers.add(("Content-Disposition", "attachment"))
  req.answer(content, headers = newHttpHeaders(headers))


proc detectReturnStmt(node: NimNode, replaceReturn: bool = false) {. compileTime .} =
  # Replaces all `return` statements with req answer*
  for i in 0..<node.len:
    var child = node[i]
    if child.kind == nnkReturnStmt and child[0].kind != nnkEmpty:
      # HTML
      if child[0].kind == nnkCall and child[0][0].kind == nnkIdent and $child[0][0] == "buildHtml":
        node[i] = newCall("answerHtml", ident"req", child[0])
      # File
      elif child[0].kind in nnkCallKinds and child[0][0].kind == nnkIdent and $child[0][0] == "FileResponse":
        node[i] = newCall("await", newCall("answerFile", ident"req", child[0][1]))
      # JSON
      elif child[0].kind in [nnkTableConstr, nnkBracket]:
        node[i] = newCall("answerJson", ident"req", child[0])
      # Any string
      elif child[0].kind in [nnkStrLit, nnkTripleStrLit]:
        when enableAutoTranslate:
          node[i] = newCall("answer", ident"req", formatNode(newCall("translate", child[0])))
        else:
          node[i] = newCall("answer", ident"req", formatNode(child[0]))
      # Variable
      else:
        when enableAutoTranslate:
          node[i] = newNimNode(nnkWhenStmt).add(
            newNimNode(nnkElifBranch).add(
              newCall("is", child[0], ident"JsonNode"),
              newCall("answerJson", ident"req", child[0])
            ),
            newNimNode(nnkElifBranch).add(
              newCall("is", child[0], ident"TagRef"),
              newCall("answerHtml", ident"req", child[0])
            ),
            newNimNode(nnkElse).add(
              newCall("answer", ident"req", newCall("translate", child[0]))
            )
          )
        else:
          node[i] = newNimNode(nnkWhenStmt).add(
            newNimNode(nnkElifBranch).add(
              newCall("is", child[0], ident"JsonNode"),
              newCall("answerJson", ident"req", child[0])
            ),
            newNimNode(nnkElifBranch).add(
              newCall("is", child[0], ident"TagRef"),
              newCall("answerHtml", ident"req", child[0])
            ),
            newNimNode(nnkElse).add(
              newCall("answer", ident"req", child[0])
            )
          )
    else:
      node[i].detectReturnStmt(true)
  # Replace last node
  if replaceReturn or node.kind in AtomicNodes:
    return
  if node[^1].kind in [nnkCall, nnkCommand]:
    if node[^1][0].kind == nnkIdent and re"^(answer|echo|translate)" in $node[^1][0]:
      return
    elif node[^1][0].kind == nnkDotExpr and ($node[^1][0][1]).toLower().startsWith("answer"):
      return
  if not node[^1].isExpr:
    return
  if node[^1].kind == nnkCall and $node[^1][0] == "buildHtml":
    node[^1] = newCall("answerHtml", ident"req", node[^1])
  elif node[^1].kind == nnkTableConstr:
    node[^1] = newCall("answerJson", ident"req", node[^1])
  elif node[^1].kind in [nnkStrLit, nnkTripleStrLit]:
    when enableAutoTranslate:
      node[^1] = newCall("answer", ident"req", formatNode(newCall("translate", node[^1])))
    else:
      node[^1] = newCall("answer", ident"req", formatNode(node[^1]))
  else:
    when enableAutoTranslate:
      node[^1] = newCall("answer", ident"req", newCall("translate", node[^1]))
    else:
      node[^1] = newCall("answer", ident"req", node[^1])


macro `~`*(strTable: StringTableRef | TableRef[string, seq[string]], key: untyped): untyped =
  ## Shortcut to get query param.
  ## 
  ## `High-level API`
  ## 
  ## ## Example
  ## 
  ## .. code-block::nim
  ##    get "/":
  ##      # exmple.com/?myParam=100
  ##      echo query~myParam
  ## 
  let
    keyStr = newStrLitNode($key)
  newCall("getOrDefault", strTable, keyStr)


macro routes*(server: Server, body: untyped): untyped =
  ## You can create routes with this marco
  ## 
  ## #### Available Path Params
  ## - `bool`: any boolean (`y`, `yes`, `on`, `1` and `true` for true; `n`, `no`, `off`, `0` and `false` for false).
  ## - `int`: any integer.
  ## - `float`: any float number.
  ## - `word`: any word includes `re"\w+"`.
  ## - `string`: any string excludes `"/"`.
  ## - `enum(EnumName)`: any string excludes `"/"`. Converts into `EnumName`.
  ## - `path`: any float number includes `"/"`.
  ## - `regex`: any regex pattern excludes groups. Usage - `"/path{pattern:/yourRegex/}"`
  ## 
  ## #### Available Route Types
  ## - `"/path/with/{args:path}"`: Just string with route path. Matches any request method
  ## - `get "/path/{args:word}"`: Route with request method. Method can be`get`, `post`, `patch`, etc.
  ## - `notfound`: Route that matches when no other matched.
  ## - `middleware`: Always executes first.
  ## - `finalize`: Executes when server is closing
  ## 
  ## #### Route Scope:
  ## - `req`: Current request
  ## - `urlPath`: Current url path
  ## - `query`: Current url path queries
  ## - `queryArr`: Current url path queries (usable for seq[string])
  ## - `wsConnections`: All websocket connections
  ## 
  ## #### Available Websocket Routing
  ## - `ws "/path/to/websockets/{args:word}`: Route with websockets
  ## - `wsConnect`: Calls on any websocket client was connected
  ## - `wsClosed`: Calls on any websocket client was disconnected
  ## - `wsMismatchProtocol`: Calls on mismatch protocol
  ## - `wsError`: Calls on any other ws error
  ## 
  ## #### Websocket Scope:
  ## - `req`: Current request
  ## - `urlPath`: Current url path
  ## - `query`: Current url path queries
  ## - `queryArr`: Current url path queries (usable for seq[string])
  ## - `wsClient`: Current websocket client
  ## - `wsConnections`: All websocket connections
  ## 
  ## # Example
  ## 
  ## .. code-block:: nim
  ##    var myServer = newServer()
  ##    myServer.routes:
  ##      "/":
  ##        "root"
  ##      "/user{id:int}":
  ##        "hello, user {id}!"
  ##      middleware:
  ##        echo req
  ##      notfound:
  ##        "Oops! Not found!"
  let
    pathIdent = ident"urlPath"
  var
    # Handle requests
    stmtList = newStmtList()
    ifStmt = newNimNode(nnkIfStmt)
    notFoundNode = newEmptyNode()
    wsNewConnection = newStmtList()
    wsClosedConnection = newStmtList()
    wsMismatchProtocol = newStmtList()
    variables = newStmtList()
    wsError = newStmtList()
    procStmt = newProc(
      ident"handleRequest",
      [newEmptyNode(), newIdentDefs(ident"req", ident"Request")],
      stmtList
    )
    caseRequestMethodsStmt = newNimNode(nnkCaseStmt)
    methodTable = newTable[string, NimNode]()
    finalize = newStmtList()

  when enableHttpx or enableHttpBeast:
    var path = newNimNode(nnkBracketExpr).add(
      newCall("split", newCall("get", newCall("path", ident"req")), newStrLitNode("?")),
      newIntLitNode(0)
    )
    let
      reqMethod = newCall("get", newDotExpr(ident"req", ident"httpMethod"))
      headers = newCall("get", newDotExpr(ident"req", ident"headers"))
      acceptLanguage = newNimNode(nnkBracketExpr).add(
        newCall(
          "split", newNimNode(nnkBracketExpr).add(headers, newStrLitNode("accept-language")), newLit(',')
        ), newLit(0)
      )
      val = ident(fmt"_val")
      url = newStmtList(
        newLetStmt(val, newCall("split", newCall("get", newCall("path", ident"req")), newStrLitNode("?"))),
        newNimNode(nnkIfStmt).add(
          newNimNode(nnkElifBranch).add(
            newCall(">=", newCall("len", val), newIntLitNode(2)),
            newNimNode(nnkBracketExpr).add(val, newIntLitNode(1))
          ), newNimNode(nnkElse).add(
            newStrLitNode("")
          )
        )
      )
  else:
    var path = newDotExpr(newDotExpr(ident"req", ident"url"), ident"path")
    let
      reqMethod = newDotExpr(ident"req", ident"reqMethod")
      headers = newDotExpr(ident"req", ident"headers")
      acceptLanguage = newNimNode(nnkBracketExpr).add(
        newCall(
          "split", newNimNode(nnkBracketExpr).add(headers, newStrLitNode("accept-language")), newLit(',')
        ), newLit(0)
      )
      url = newDotExpr(newDotExpr(ident"req", ident"url"), ident"query")
  let
    directoryFromPath = newCall(
      "&",
      newStrLitNode("."),
      newCall("replace", pathIdent, newLit('/'), ident"DirSep")
    )
    cookiesOutVar = newCall(newNimNode(nnkBracketExpr).add(ident"newSeq", ident"string"))
    cookiesInVar = newNimNode(nnkIfStmt).add(
      newNimNode(nnkElifBranch).add(
        newCall("hasKey", headers, newStrLitNode("cookie")),
        newCall("parseCookies", newCall("$", newNimNode(nnkBracketExpr).add(headers, newStrLitNode("cookie"))))
      ), newNimNode(nnkElse).add(
        newCall("parseCookies", newStrLitNode(""))
      )
    )
    isWebsocketConnection =
      newCall(
        "and",
        newCall(
          "and",
          newCall("hasKey", headers, newStrLitNode("connection")),
          newCall("hasKey", headers, newStrLitNode("upgrade")),
        ),
        newCall(
          "and",
          newCall("==", newCall("toLower", newCall("[]", headers, newStrLitNode("connection"), newLit(0))), newStrLitNode("upgrade")),
          newCall("==", newCall("toLower", newCall("[]", headers, newStrLitNode("upgrade"), newLit(0))), newStrLitNode("websocket")),
        )
      )
  
  when defined(debug):
    caseRequestMethodsStmt.add(ident"reqMethod")
  else:
    caseRequestMethodsStmt.add(reqMethod)
  
  procStmt.addPragma(ident"async")

  # Find mounts
  body.findAndReplaceMount()

  for key in sugarRoutes.keys():
    if sugarRoutes[key].httpMethod.toLower() == "any":
      body.add(newCall(newStrLitNode(key), sugarRoutes[key].body))
    elif sugarRoutes[key].httpMethod.toLower() in httpMethods:
      body.add(newNimNode(nnkCommand).add(
        ident(sugarRoutes[key].httpMethod),
        newStrLitNode(key),
        sugarRoutes[key].body
      ))
  
  for statement in body:
    if statement.kind in [nnkCall, nnkCommand]:
      if statement[^1].kind == nnkStmtList:
        # Check variable usage
        if statement[^1].isIdentUsed(ident"statusCode"):
          statement[^1].insert(0, newVarStmt(ident"statusCode", newLit(200)))
        if statement[^1].isIdentUsed(ident"cookies"):
          statement[^1].insert(0, newVarStmt(ident"cookies", cookiesOutVar))
      # "/...": statement list
      if statement[1].kind == nnkStmtList and statement[0].kind == nnkStrLit:
        detectReturnStmt(statement[1])
        let exported = exportRouteArgs(pathIdent, statement[0], statement[1])
        if exported.len > 0:  # /my/path/with{custom:int}/{param:path}
          ifStmt.add(exported)
        else:  # /just-my-path
          ifStmt.add(newNimNode(nnkElifBranch).add(
            newCall("==", pathIdent, statement[0]), statement[1]
          ))
      # notfound: statement list
      elif statement[1].kind == nnkStmtList and statement[0].kind == nnkIdent:
        case ($statement[0]).toLower()
        of "wsconnect":
          wsNewConnection = statement[1]
        of "wsclosed":
          wsClosedConnection = statement[1]
        of "wsmismatchprotocol":
          wsMismatchProtocol = statement[1]
        of "wserror":
          wsError = statement[1]
        of "finalize":
          finalize = statement[1]
        of "notfound":
          detectReturnStmt(statement[1])
          notFoundNode = statement[1]
        of "middleware":
          detectReturnStmt(statement[1])
          stmtList.insert(0, statement[1])
        else:
          throwDefect(
            HpxServeRouteDefect,
            "Wrong serve route detected ",
            lineInfoObj(statement[0])
          )
      # reqMethod "/...":
      #   ...
      elif statement[0].kind == nnkIdent and statement[0] != ident"mount" and statement[1].kind in [nnkStrLit, nnkTripleStrLit, nnkInfix]:
        let name = ($statement[0]).toUpper()
        if name == "STATICDIR":
          if statement[1].kind in [nnkStrLit, nnkTripleStrLit]:
            ifStmt.insert(
              0, newNimNode(nnkElifBranch).add(
                newCall(
                  "and",
                  newCall(
                    "or",
                    newCall("startsWith", pathIdent, statement[1]),
                    newCall("startsWith", pathIdent, newStrLitNode("/" & $statement[1])),
                  ), newCall(
                    "fileExists",
                    directoryFromPath
                  )
                ),
                newStmtList(
                  newCall("await", newCall("answerFile", ident"req", directoryFromPath))
                )
              )
            )
          else:
            let
              route = if $statement[1][1] == "/": newStrLitNode("") else: statement[1][1]
              path = if $statement[1][1] == "/": newStrLitNode($statement[1][2] & "/") else: statement[1][2]
              replace = if $statement[1][1] == "/": newStrLitNode(".") else: newCall("&", newStrLitNode("."), newLit("/"))
            let dirFromPath = newCall(
              "&",
              newCall("&", newStrLitNode("."), newLit("/")),
              newCall(
                "replace",
                newCall("replace", pathIdent, statement[1][1], path),
                newLit('/'), ident"DirSep"
              )
            )
            ifStmt.insert(
              0, newNimNode(nnkElifBranch).add(
                newCall(
                  "and",
                  newCall("startsWith", pathIdent, route),
                  newCall("fileExists", dirFromPath)
                ),
                newStmtList(
                  newCall("await", newCall("answerFile", ident"req", dirFromPath))
                )
              )
            )
          continue
        let exported = exportRouteArgs(pathIdent, statement[1], statement[2])
        # Handle websockets
        if name == "WS":
          var
            insertWsList = newStmtList()
            wsDelStmt = newStmtList(
              newCall(
                "del",
                ident"wsConnections",
                newCall("find", ident"wsConnections", ident"wsClient"))
            )
          when enableHttpx:
            wsDelStmt.add(
              newCall("close", ident"wsClient")
            )
          when enableHttpBeast:
            let asyncFd = newDotExpr(newDotExpr(ident"req", ident"client"), ident"AsyncFD")
            let wsStmtList = newStmtList(
              newLetStmt(
                ident"headers",
                newCall("get", newDotExpr(ident"req", ident"headers"))
              ),
              newCall("forget", ident"req"),
              newCall("register", asyncFd),
              newLetStmt(ident"socket", newCall("newAsyncSocket", asyncFd)),
              newMultiVarStmt(
                [ident"wsClient", ident"error"],
                newCall("await", newCall("verifyWebsocketRequest", ident"socket", ident"headers", newLit(""))),
                true
              ),
              newNimNode(nnkIfStmt).add(newNimNode(nnkElifBranch).add(
                newCall("isNil", ident"wsClient"),
                newStmtList(
                  newCall("close", ident"socket")
                )
              ), newNimNode(nnkElse).add(newStmtList(
                newCall("add", ident"wsConnections", ident"wsClient"),
                wsNewConnection,
                newNimNode(nnkWhileStmt).add(newLit(true), newStmtList(
                  newMultiVarStmt(
                    [ident"opcode", ident"wsData"],
                    newCall("await", newCall("readData", ident"wsClient")),
                    true
                  ),
                  newCall("echo", ident"wsData"),
                  newNimNode(nnkTryStmt).add(
                    # TRY
                    newStmtList(
                      newNimNode(nnkIfStmt).add(newNimNode(nnkElifBranch).add(
                        newCall("==", ident"opcode", newDotExpr(ident"Opcode", ident"Close")),
                        newStmtList(
                          when enableDebug:
                            newStmtList(
                              newCall("error", newStrLitNode("Socket closed")),
                              wsDelStmt,
                              wsClosedConnection
                            )
                          else:
                            if wsClosedConnection.len == 0:
                              wsDelStmt
                            else:
                              wsClosedConnection.add(wsDelStmt),
                          newNimNode(nnkBreakStmt).add(newEmptyNode())
                        )
                      )),
                      insertWsList
                    # OTHER WS ERROR
                    ), newNimNode(nnkExceptBranch).add(
                      when enableDebug:
                        newStmtList(
                          newCall(
                            "error",
                            newCall("fmt", newStrLitNode("Unexpected socket error: {getCurrentExceptionMsg()}"))
                          ),
                          wsDelStmt,
                          wsError
                        )
                      else:
                        if wsError.len == 0:
                          wsDelStmt
                        else:
                          wsError.add(wsDelStmt)
                    )
                  )
                ))
              ))),
            )
          else:
            let wsStmtList = newStmtList(
              newLetStmt(ident"wsClient", newCall("await", newCall("newWebSocket", ident"req"))),
              newCall("add", ident"wsConnections", ident"wsClient"),
              newNimNode(nnkTryStmt).add(
                newStmtList(
                  wsNewConnection,
                  newNimNode(nnkWhileStmt).add(
                    newCall("==", newDotExpr(ident"wsClient", ident"readyState"), ident"Open"),
                    newStmtList(
                      newLetStmt(ident"wsData", newCall("await", newCall("receiveStrPacket", ident"wsClient"))),
                      insertWsList
                    )
                  )
                ),
                newNimNode(nnkExceptBranch).add(
                  ident"WebSocketClosedError",
                  when enableDebug:
                    newStmtList(
                      newCall(
                        "error", newCall("fmt", newStrLitNode("Socket closed: {getCurrentExceptionMsg()}"))
                      ),
                      wsDelStmt,
                      wsClosedConnection
                    )
                  else:
                    if wsClosedConnection.len == 0:
                      wsDelStmt
                    else:
                      wsClosedConnection.add(wsDelStmt)
                ),
                newNimNode(nnkExceptBranch).add(
                  ident"WebSocketProtocolMismatchError",
                  when enableDebug:
                    newStmtList(
                      newCall(
                        "error",
                        newCall("fmt", newStrLitNode("Socket tried to use an unknown protocol: {getCurrentExceptionMsg()}"))
                      ),
                      wsDelStmt,
                      wsMismatchProtocol
                    )
                  else:
                    if wsMismatchProtocol.len == 0:
                      wsDelStmt
                    else:
                      wsMismatchProtocol.add(wsDelStmt)
                ),
                newNimNode(nnkExceptBranch).add(
                  ident"WebSocketError",
                  when enableDebug:
                    newStmtList(
                      newCall(
                        "error",
                        newCall("fmt", newStrLitNode("Unexpected socket error: {getCurrentExceptionMsg()}"))
                      ),
                      wsDelStmt,
                      wsError
                    )
                  else:
                    if wsError.len == 0:
                      wsDelStmt
                    else:
                      wsError.add(wsDelStmt)
                )
              )
            )
          if not methodTable.hasKey("GET"):
            methodTable["GET"] = newNimNode(nnkIfStmt)
          if exported.len > 0:
            insertWsList.add(exported[1])
            exported[1].add(wsStmtList)
            methodTable["GET"].add(exported)
          else:
            insertWsList.add(statement[2])
            methodTable["GET"].add(newNimNode(nnkElifBranch).add(
              newCall("and", isWebsocketConnection, newCall("==", pathIdent, statement[1])),
              wsStmtList
            ))
          continue
        let methodName = $name
        if not methodTable.hasKey(methodName):
          methodTable[methodName] = newNimNode(nnkIfStmt)
        if exported.len > 0:  # /my/path/with{custom:int}/{param:path}
          detectReturnStmt(exported[1])
          methodTable[methodName].add(exported)
        else:  # /just-my-path
          detectReturnStmt(statement[2])
          methodTable[methodName].add(newNimNode(nnkElifBranch).add(
            newCall("==", pathIdent, statement[1]),
            statement[2]
          ))
    elif statement.kind in [nnkVarSection, nnkLetSection]:
      variables.add(statement)
  
  let
    immutableVars = newNimNode(nnkLetSection).add(
      newIdentDefs(ident"urlPath", newEmptyNode(), path),
    )
    mutableVars = newNimNode(nnkVarSection)

  # immutable variables
  stmtList.insert(0, immutableVars)
  stmtList.insert(0, mutableVars)
  
  when enableDebug:
    stmtList.add(newCall(
      "info",
      newCall("fmt", newStrLitNode("{reqMethod}::{urlPath}"))
    ))
  
  stmtList.add(caseRequestMethodsStmt)
  for key in methodTable.keys():
    caseRequestMethodsStmt.add(newNimNode(nnkOfBranch).add(
      newLit(parseEnum[HttpMethod](key)),
      methodTable[key]
    ))
  caseRequestMethodsStmt.add(newNimNode(nnkElse).add(newStmtList()))

  if ifStmt.len > 0:
    stmtList.add(ifStmt)
    # return 404
    if notFoundNode.kind == nnkEmpty:
      let elseStmtList = newStmtList()
      ifStmt.add(newNimNode(nnkElse).add(elseStmtList))
      when enableDebug:
        elseStmtList.add(
          newCall(
            "warn",
            newCall(
              "fgColored", 
              newCall("fmt", newStrLitNode("{urlPath} is not found.")), ident"fgYellow"
            )
          )
        )
      elseStmtList.add(
        newCall(ident"answer", ident"req", newStrLitNode("Not found"), ident"Http404")
      )
    else:
      ifStmt.add(newNimNode(nnkElse).add(notFoundNode))
  else:
    # return 404
    if notFoundNode.kind == nnkEmpty:
      when enableDebug:
        stmtList.add(newCall(
          "warn",
          newCall(
            "fgColored",
            newCall("fmt", newStrLitNode("{urlPath} is not found.")), ident"fgYellow"
          )
        ))
      stmtList.add(
        newCall(ident"answer", ident"req", newStrLitNode("Not found"), ident"Http404")
      )
    else:
      stmtList.add(notFoundNode)
  result = newStmtList(
    if stmtList.isIdentUsed(ident"wsConnections"):
      newNimNode(nnkVarSection).add(newIdentDefs(
        ident"wsConnections",
        when enableHttpBeast:
          newNimNode(nnkBracketExpr).add(ident"seq", ident"AsyncWebSocket")
        else:
          newNimNode(nnkBracketExpr).add(ident"seq", ident"WebSocket"),
        newCall("@", newNimNode(nnkBracket)),
      ))
    else:
      newEmptyNode(),
    procStmt,
    newProc(
      ident"finalizeProgram",
      [newEmptyNode()],
      finalize,
      pragmas = newNimNode(nnkPragma).add(ident"noconv")
    )
  )

  for v in countdown(variables.len-1, 0, 1):
    result.insert(0, variables[v])
  
  if stmtList.isIdentUsed(ident"query"):
    immutableVars.add(newIdentDefs(ident"queryFromUrl", newEmptyNode(), url))
    immutableVars.add(newIdentDefs(ident"query", newEmptyNode(), newCall("parseQuery", ident"queryFromUrl")))
    immutableVars.add(newIdentDefs(ident"queryArr", newEmptyNode(), newCall("parseQueryArrays", ident"queryFromUrl")))
  if stmtList.isIdentUsed(ident"translate"):
    immutableVars.add(newIdentDefs(ident"acceptLanguage", newEmptyNode(), acceptLanguage))
  if stmtList.isIdentUsed(ident"inCookies"):
    immutableVars.add(newIdentDefs(ident"inCookies", newEmptyNode(), cookiesInVar))
  when defined(debug):
    if stmtList.isIdentUsed(ident"reqMethod"):
      immutableVars.add(newIdentDefs(ident"reqMethod", newEmptyNode(), reqMethod))


macro initServer*(body: untyped): untyped =
  ## Shortcut for
  ## 
  ## ⚠ `Low-level API` ⚠
  ## 
  ## .. code-block:: nim
  ##    proc main() {.gcsafe.} =
  ##      `body`
  ##    main()
  ## 
  body.insert(0, translatesStatement)
  result = newStmtList(
    newProc(
      ident"main",
      [newEmptyNode()],
      body.add(
        newCall("addQuitProc", ident"finalizeProgram")
      ),
      nnkProcDef
    ),
    newCall("main")
  )
  result[0].addPragma(ident"gcsafe")
    

when enableApiDoc:
  proc fetchPathParams*(route: var string): NimNode =
    var
      params = newNimNode(nnkBracket)
    let
      dollarToCurve = re"\$([^:\/\{\}]+)(:enum\(\w+\)|:\w+)?(\[m\])?(=[^\/\{\}]+)?(m)?"
      defaultWithoutQuestion = re"\{([^:\/\{\}\?]+)(:enum\(\w+\)|:\w+)?(\[m\])?(=[^\/\{\}]+)\}"
    
    route = route.replace(dollarToCurve, "{$1$2$3$4}")
    route = route.replace(defaultWithoutQuestion, "{$1?$2$3$4}")

    let
      found = route.findAll(
        re"\{([a-zA-Z][a-zA-Z0-9_]*\??)(:(bool|int|float|string|path|word|/[\s\S]+?/|enum\(\w+\)))?(\[m\])?(=(\S+?))?\}"
      )
      foundModels = route.findAll(
        re"\[([a-zA-Z][a-zA-Z0-9_]*):([a-zA-Z][a-zA-Z0-9_]*)(\[m\])?(:[a-zA-Z\\-]+)?\]"
      )
    for i in found:
      # Detect other data
      let
        argTypeStr =
          if i.group(2, route).len == 0:
            "string"
          else:
            i.group(2, route)[0]
        defaultVal =
          if i.group(5, route).len == 0:
            ""
          else:
            i.group(5, route)[0]
        isMutable = i.group(3, route).len != 0
      # Detect main data
      var
        name = i.group(0, route)[0]
        isOptional = false
      # Detect optional value
      if name.endsWith(re"\?"):
        name = name[0..^2]
        isOptional = true
      elif defaultVal.len > 0:
        isOptional = true
      
      params.add(newCall(
        "newApiDocPathParamObject",
        newStrLitNode(name),
        newStrLitNode(argTypeStr),
        newStrLitNode(defaultVal),
        newLit(isOptional),
        newLit(isMutable),
      ))
    
    route = route.replace(
      re"\{([a-zA-Z][a-zA-Z0-9_]*)\??(:(bool|int|float|string|path|word|/[\s\S]+?/|enum\(\w+\)))?(\[m\])?(=(\S+?))?\}",
      "{$1}"
    )

    newCall("@", params)


  proc genApiDoc*(body: var NimNode): NimNode =
    ## Returns API route
    var
      docsData = newNimNode(nnkBracket)
      bodyCopy = body.copy()
    bodyCopy.findAndReplaceMount()
    for i in bodyCopy:
      if i.kind in [nnkCall, nnkCommand]:
        if i[0].kind == nnkIdent and i.len == 3 and i[2].kind == nnkStmtList and i[1].kind == nnkStrLit:
          ## HTTP Method
          var
            description = ""
            pathParam = $i[1]
            params = fetchPathParams(pathParam)
          for statement in i[2]:
            if statement.kind == nnkCommentStmt:
              description &= $statement & "\n"
          docsData.add(newCall(
            "newApiDocObject",
            newStrLitNode(($i[0].toStrLit).toUpper()),  # HTTP Method
            newStrLitNode(description),  # Description
            newStrLitNode(pathParam),  # Path
            params
          ))
        elif i[0].kind == nnkStrLit and i.len == 2 and i[1].kind == nnkStmtList:
          ## HTTP Method
          var
            description = ""
            pathParam = $i[0]
            params = fetchPathParams(pathParam)
          for statement in i[1]:
            if statement.kind == nnkCommentStmt:
              description &= $statement & "\n"
          docsData.add(newCall(
            "newApiDocObject",
            newStrLitNode(""),  # HTTP Method
            newStrLitNode(description),  # Description
            newStrLitNode(pathParam),  # Path
            params
          ))
        
    # Get all documentation
    body.add(newNimNode(nnkCommand).add(ident"get", newStrLitNode(
      if apiDocsPath.startsWith("/"):
        apiDocsPath
      else:
        "/" & apiDocsPath
    ), newStmtList(
      newCall("answerHtml", ident"req", newCall("renderDocsProcedure")),
    )))
    newCall("@", docsData)


macro serve*(address: string, port: int, body: untyped): untyped =
  ## Initializes a new server and start it. Shortcut for
  ## 
  ## `High-level API`
  ## 
  ## .. code-block:: nim
  ##    proc main() =
  ##      var server = newServer(`address`, `port`)
  ##      server.routes:
  ##        `body`
  ##      server.start()
  ##    main()
  ## 
  ## For GC Safety you can declare your variables inside `serve` macro ✌
  ## 
  ## .. code-block:: nim
  ##    serve(...):
  ##      var index = 0
  ##      let some = "some"
  ##      
  ##      "/":
  ##        inc index
  ##        return {"index": index}
  ##      
  ##      "/some":
  ##        return some
  ## 
  var bodyStatement = body
  when enableApiDoc:
    echo port.toStrLit
    var docsData = bodyStatement.genApiDoc()

  result = newStmtList(
    newProc(
      ident"main",
      [newEmptyNode()],
      newStmtList(
        newVarStmt(
          ident"server",
          newCall("newServer", address, port)
        ),
        when enableApiDoc:
          newProc(ident"renderDocsProcedure", [ident"string"], newStmtList(
            newLetStmt(ident"title", newStrLitNode(appName)),
            newNimNode(nnkLetSection).add(
              newIdentDefs(
                ident"apiDocData", newNimNode(nnkBracketExpr).add(ident"seq", ident"ApiDocObject"), docsData
              )
            ),
            newCall("compileTemplateStr", newStrLitNode(IndexApiDocPageTemplate)),
          ))
        else:
          newEmptyNode(),
        translatesStatement,
        newCall("routes", ident"server", body),
        newCall("start", ident"server"),
        newCall("addQuitProc", ident"finalizeProgram")
      ),
      nnkProcDef
    ),
    newCall("main")
  )
  result[0].addPragma(ident"gcsafe")
