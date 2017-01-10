class ner_complete extends AnnotationIteration

  _this = undefined
  tokensQuery = '.interfaces-staging >:not(.template) .paragraph-container .token'

  # uncomment to overwrite interface registration at AnnotationLifecylce
  constructor: ->
    _this = this
    this.$tokens = $(tokensQuery)
    this.tokens = []
    this.selectedTokenIndex = -1
    this.knownKeys = [8, 9, 16, 37, 39, 49, 50, 74, 75]
    this.keyMap = []
    this.currentDraggingStartedAtTokenIndex = -1
    this.preventClickOnToken = false
    this.registeredEventListeners = []

    # iterate over all tokens and save them in an array
    this.initTokens()
    this.initKeyboardEventHandler()
    this.initMouseEventHandler()

    super

  initTokens: ->
    this.iterationMemory = { count: 0, kind: '', leftSiblingIndex: -1 }
    this.$tokens.each (index, element) ->
      $token = $(element)
      kind = 'COM' if $token.hasClass('COM')
      kind = 'PER' if $token.hasClass('PER')

      # this is a subsequent annotation
      if _this.iterationMemory.count > 0
        kind = _this.iterationMemory.kind
        leftSiblingIndex = _this.iterationMemory.leftSiblingIndex
        _this.addTokenToList($token, kind, index, leftSiblingIndex)
        _this.iterationMemory.count = _this.iterationMemory.count - 1
        _this.iterationMemory.leftSiblingIndex = index
        $token.addClass('right-end') if _this.iterationMemory.count == 0

      # this is a newly detected annotation
      else if kind
        _this.addTokenToList($token, kind, index, -1)
        tokenLength = $token.data('token-length')
        $token.addClass('left-end')
        $token.addClass('right-end') if tokenLength == 1
        if tokenLength > 1
          _this.iterationMemory = {
            count: (tokenLength - 1),
            kind: kind,
            leftSiblingIndex: index
          }

  initKeyboardEventHandler: ->
    $(document).off 'keydown'
    $(document).keydown (e) ->
      returnStatement = true
      returnStatement = false if _this.knownKeys.indexOf(e.keyCode) >= 0
      return returnStatement unless _this.keyMap.indexOf(e.keyCode) == -1

      _this.keyMap.push(e.keyCode)
      _this.actionFromKeyEvent()
      return returnStatement

    $(document).off 'keyup'
    $(document).keyup (e) ->
      keyMapIndex = _this.keyMap.indexOf(e.keyCode)
      _this.keyMap.splice(keyMapIndex)

  initMouseEventHandler: ->
    $('.interfaces-staging .token').mousedown ->
      # return if _this.preventClickOnToken
      $clickedToken = $(this)
      clickedTokenIndex = _this.selectChunkWithToken($clickedToken)
      _this.currentDraggingStartedAtTokenIndex = clickedTokenIndex

      $chainableTokens = $('.token', $clickedToken.parent())
      $chainableTokens.css('cursor', 'ew-resize')

      $leftHandle = $clickedToken.find('.chunk-size-handle-left')
      $rightHandle = $clickedToken.find('.chunk-size-handle-right')
      if $leftHandle.is(':hover') || $rightHandle.is(':hover')
        # the left or right handle is clicked; remove or append tokens
        if $leftHandle.is(':hover')
          side = 'left'
          $clickedHandle = $leftHandle
        else
          side = 'right'
          $clickedHandle = $rightHandle

        # case 1: move to the left

        # case 2: shrink the chunk;
        $clickedHandle.mouseout ->
          _this.registerEventListener($(this), 'mouseout')
          $deletableTokens = _this.selectionOfDeletableTokensFrom(side)
          return unless $deletableTokens

          $deletableTokens.mousemove ->
            _this.registerEventListener($deletableTokens, 'mousemove')

            if !$clickedHandle.is(':hover')
              _this.removeTokenFromChunk(side)
              $(this).off 'mousemove'

      else
        # a token in the current chunk is clicked; dragging recreates the current chunk
        $chainableTokens.mouseenter ->
          return if _this.currentDraggingStartedAtTokenIndex < 0
          _this.registerEventListener($chainableTokens, 'mouseenter')
          hoveredTokenIndex = _this.selectChunkWithToken($(this))
          _this.createChunkWithTokens(clickedTokenIndex, hoveredTokenIndex)

    $('body').mouseup (e) ->
      console.log 'mouse released'
      _this.removeRegisteredEventListeners()
      _this.$tokens.css('cursor', 'crosshair')
      _this.preventClickOnToken = false
      _this.currentDraggingStartedAtTokenIndex = -1

  actionFromKeyEvent: ->
    keyIsPressed = (keyId) ->
      _this.keyMap.indexOf(keyId) >= 0

    _this.saveAnnotation() if keyIsPressed(74) # key 'j'
    _this.skip() if keyIsPressed(75) # key 'k'

    # all other bindings require a token to be selected
    return if this.selectedTokenIndex < 0

    # backspace
    if keyIsPressed(8)
      _this.removeChunkWithIndex(this.selectedTokenIndex)

    # shift
    if keyIsPressed(16)
      _this.removeTokenFromChunk('left') if keyIsPressed(37) # key '->'
      _this.removeTokenFromChunk('right') if keyIsPressed(39) # key '->'
      _this.selectNextChunk('left') if keyIsPressed(9) # key 'tab'

    else
      _this.changeTokenKind('PER') if keyIsPressed(49) # key '1'
      _this.changeTokenKind('COM') if keyIsPressed(50) # key '2'
      _this.addTokenToChunk('left') if keyIsPressed(37) # key '<-'
      _this.addTokenToChunk('right') if keyIsPressed(39) # key '->'
      _this.selectNextChunk('right') if keyIsPressed(9) # key 'tab'

  createChunkWithTokens: (clickedTokenIndex, hoveredTokenIndex, newSelection=true) ->
    # find first / last and check if one or both belong to a chunk (and get real first / last indices)
    if clickedTokenIndex < hoveredTokenIndex
      firstIndex = clickedTokenIndex if newSelection
      firstIndex = this.getMostOuterTokenIndexFromChunk(clickedTokenIndex, 'left') unless newSelection
      lastIndex = hoveredTokenIndex
    else
      firstIndex = hoveredTokenIndex
      lastIndex = clickedTokenIndex if newSelection
      lastIndex = this.getMostOuterTokenIndexFromChunk(clickedTokenIndex, 'right') unless newSelection

    # remove clicked chunk and hovered chunk
    this.removeChunkWithIndex(this.selectedTokenIndex)
    unless this.tokensBelongToSameChunk(firstIndex, lastIndex)
      this.removeChunkWithIndex(firstIndex) if clickedTokenIndex < hoveredTokenIndex
      this.removeChunkWithIndex(lastIndex) if clickedTokenIndex > hoveredTokenIndex

    # build chunk from start to end
    this.addNewToken(this.tokens[firstIndex].$token, firstIndex)
    this.addTokenToChunk('right') for [1..(lastIndex - firstIndex)] unless firstIndex == lastIndex

  addTokenToChunk: (side) ->
    mostOuterTokenIndex = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, side)
    mostOuterToken = this.tokens[mostOuterTokenIndex]
    kind = mostOuterToken.kind
    targetIndex = if side == 'left' then mostOuterTokenIndex - 1 else mostOuterTokenIndex + 1
    return if targetIndex < 0 || targetIndex >= this.$tokens.length

    mostOuterToken.$token.removeClass("#{side}-end")
    $token = $(this.$tokens.get(targetIndex))
    this.removeChunkWithIndex(targetIndex) if $token.data('token-id') >= 0
    $token.addClass("selected #{side}-end")

    if side == 'left'
      _this.addTokenToList($token, kind, targetIndex, -1)
      mostOuterToken.leftSiblingIndex = targetIndex
      this.tokens[targetIndex].rightSiblingIndex = mostOuterTokenIndex

    else if side == 'right'
      _this.addTokenToList($token, kind, targetIndex, mostOuterTokenIndex)
      mostOuterToken.rightSiblingIndex = targetIndex
      this.tokens[targetIndex].leftSiblingIndex = mostOuterTokenIndex

  addNewToken: ($token, index) ->
    _this.addTokenToList($token, 'PER', index, -1)
    $token.addClass('left-end')
    $token.addClass('right-end')
    this.changeTokenState(this.selectedTokenIndex, false)
    this.selectedTokenIndex = index
    this.changeTokenState(this.selectedTokenIndex, true)

  removeTokenFromChunk: (side) ->
    mostOuterTokenIndex = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, side)
    mostOuterToken = this.tokens[mostOuterTokenIndex]
    return if mostOuterToken.leftSiblingIndex < 0 && mostOuterToken.rightSiblingIndex < 0

    if side == 'left'
      siblingIndex = mostOuterToken.rightSiblingIndex
      this.tokens[siblingIndex].leftSiblingIndex = -1
      mostOuterToken.rightSiblingIndex = -1

    else if side == 'right'
      siblingIndex = mostOuterToken.leftSiblingIndex
      this.tokens[siblingIndex].rightSiblingIndex = -1
      mostOuterToken.leftSiblingIndex = -1

    if siblingIndex >= 0
      mostOuterToken.$token.removeClass("#{side}-end")
      this.tokens[siblingIndex].$token.addClass("#{side}-end")

    mostOuterToken.$token.removeClass(mostOuterToken.kind)
    mostOuterToken.$token.removeClass('selected')
    this.selectedTokenIndex = siblingIndex if this.selectedTokenIndex == mostOuterTokenIndex

  removeChunkWithIndex: (tokenIndex) ->
    mostOuterTokenIndex = this.getMostOuterTokenIndexFromChunk(tokenIndex, 'left')
    this.removeChunkWithStartIndex(mostOuterTokenIndex)

  removeChunkWithStartIndex: (mostOuterTokenIndex) ->
    modifier = (token, selected) ->
      token.$token.removeClass('PER COM left-end right-end selected')
      token.$token.data('token-id', -1)
      leftSiblingIndex = token.leftSiblingIndex
      if leftSiblingIndex >= 0
        leftSibling = _this.tokens[leftSiblingIndex]
        leftSibling.rightSiblingIndex = -1
      leftSiblingIndex = -1
    this.tokenIterator(mostOuterTokenIndex, modifier, false, false, true)

  selectNextChunk: (side) ->
    nextChunkId = this.findNextChunkIndex(this.selectedTokenIndex, side)
    this.selectChunkWithTokenIndex(nextChunkId)

  findNextChunkIndex: (startIndex, side) ->
    if this.tokens[startIndex]
      mostOuterTokenIndex = this.getMostOuterTokenIndexFromChunk(startIndex, side)
      queryString = ":gt(#{mostOuterTokenIndex}).left-end:first" if side == 'right'
      queryString = ":lt(#{mostOuterTokenIndex}).right-end:last" if side == 'left'
      nextChunkId = $("#{tokensQuery}#{queryString}").data('token-id')

    unless nextChunkId
      queryString = ".left-end:first" if side == 'right'
      queryString = ".left-end:last" if side == 'left'
      nextChunkId = $("#{tokensQuery}#{queryString}").data('token-id')

    nextChunkId

  tokenIsChunk: ($token) ->
    tokenIndex = $token.data('token-id')
    tokenIndex >= 0

  # tokenIsInChunk: (tokenIndex, indexOfChunkMember) ->
  #   leftBound = this.getMostOuterTokenIndexFromChunk(indexOfChunkMember, 'left')
  #   rightBound = this.getMostOuterTokenIndexFromChunk(indexOfChunkMember, 'right')
  #   leftBound <= tokenIndex <= rightBound

  selectionOfDeletableTokensFrom: (side) ->
    leftBound = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, 'left')
    rightBound = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, 'right')
    return undefined if rightBound == leftBound # a token can not be removed from this chunk

    return this.$tokens.slice(leftBound, rightBound) if side == 'left'
    this.$tokens.slice(leftBound + 1, rightBound + 1) # if side == 'right'

  tokensBelongToSameChunk: (indexA, indexB) ->
    mostOuterIndexA = this.getMostOuterTokenIndexFromChunk(indexA, 'left')
    mostOuterIndexB = this.getMostOuterTokenIndexFromChunk(indexB, 'left')
    mostOuterIndexA == mostOuterIndexB

  createChunkFromToken: ($token) ->
    jQueryIndex = $token.index(tokensQuery)
    _this.addNewToken($token, jQueryIndex)
    jQueryIndex

  selectChunkWithToken: ($token) ->
    tokenIndex = $token.data('token-id') if _this.tokenIsChunk($token)
    tokenIndex = _this.createChunkFromToken($token) unless _this.tokenIsChunk($token)
    _this.selectChunkWithTokenIndex(tokenIndex)

  selectChunkWithTokenIndex: (index) ->
    this.changeTokenState(this.selectedTokenIndex, false)
    this.changeTokenState(index, true)
    this.selectedTokenIndex = index

  getMostOuterTokenIndexFromChunk: (chunkMemberIndex, side) ->
    token = this.tokens[chunkMemberIndex]
    return chunkMemberIndex if side == 'left' && token.leftSiblingIndex == -1
    return chunkMemberIndex if side == 'right' && token.rightSiblingIndex == -1
    return this.getMostOuterTokenIndexFromChunk(token.leftSiblingIndex, side) if side == 'left'
    return this.getMostOuterTokenIndexFromChunk(token.rightSiblingIndex, side) if side == 'right'

  setCurrentAnnotationLength: (tokenIndex) ->
    this.currentAnnotationLength = 0
    modifier = (token, _) ->
      _this.currentAnnotationLength = 1 + _this.currentAnnotationLength
    this.tokenIterator(tokenIndex, modifier, false)
    this.currentAnnotationLength

  changeTokenState: (tokenIndex, selected) ->
    modifier = (token, selected) ->
      token.$token.addClass('selected') if selected
      token.$token.removeClass('selected') unless selected
    this.tokenIterator(tokenIndex, modifier, selected)

  changeTokenKind: (kind) ->
    return if this.selectedTokenIndex < 0

    modifier = (token, kind) ->
      unless token.kind == kind
        token.kind = kind
        token.$token.removeClass('PER') if kind == 'COM'
        token.$token.removeClass('COM') if kind == 'PER'
        token.$token.addClass(kind)
    this.tokenIterator(this.selectedTokenIndex, modifier, kind)

  tokenIterator: (tokenIndex, modifier, args, leftDirection, rightDirection) ->
    return if tokenIndex < 0
    token = this.tokens[tokenIndex]
    modifier(token, args)

    # iterate recursively
    if !rightDirection && token.leftSiblingIndex >= 0
      this.tokenIterator(token.leftSiblingIndex, modifier, args, true, false)
    if !leftDirection && token.rightSiblingIndex >= 0
      this.tokenIterator(token.rightSiblingIndex, modifier, args, false, true)

  addTokenToList: ($token, tokenKind, index, leftSiblingIndex) ->
    $token.addClass(tokenKind)
    $token.data('token-id', index)
    this.tokens[index] = {
      $token: $token,
      index: index,
      kind: tokenKind,
      leftSiblingIndex: leftSiblingIndex,
      rightSiblingIndex: -1
    }

    if leftSiblingIndex >= 0
      leftSibling = this.tokens[leftSiblingIndex]
      leftSibling.rightSiblingIndex = index


  registerEventListener: (selection, eventName) ->
    this.registeredEventListeners.push({
      selection: selection,
      eventName: eventName
    })

  removeRegisteredEventListeners: ->
    for listener in this.registeredEventListeners
      listener.selection.off(listener.eventName)

  # theOtherWayAround: (side) ->
  #   return 'right' if side == 'left'
  #   'left'

  render: (template, data) ->
    window.annotationDocumentPayload = data
    super

  saveAnnotation: ->
    # collect all the annotations from the UI and save them as payload
    $paragraphs = $('.interfaces-staging >:not(.template) .paragraph-container .paragraph')
    payload = {
      content: new Array()
    }
    this.tokenSkipCount = 0
    annotatedTokens = [] # debug

    $paragraphs.each (paragraphIndex, paragraphElement) ->
      payload['content'].push(new Array())
      $('.sentence', $(paragraphElement)).each (sentenceIndex, sentenceElement) ->
        payload['content'][paragraphIndex].push(new Array())
        $('.token', $(sentenceElement)).each (_, tokenElement) ->
          $token = $(tokenElement)
          tokenHash = {
            term: $token.html().replace(/^\s+|\s+$/g, '')
          }

          tokenId = $token.data('token-id')
          if tokenId >= 0 && _this.tokenSkipCount == 0
            _this.tokenSkipCount = (_this.setCurrentAnnotationLength(tokenId) - 1)
            tokenHash['annotation'] = {
              label: _this.tokens[tokenId].kind,
              length: _this.currentAnnotationLength
            }
            annotatedTokens.push(tokenHash) # debug

          else if _this.tokenSkipCount > 0
            _this.tokenSkipCount = _this.tokenSkipCount - 1

          payload['content'][paragraphIndex][sentenceIndex].push(tokenHash)

    console.log annotatedTokens.length, 'annotated tokens:', annotatedTokens # debug
    this.saveChanges(payload)

window.ner_complete = new ner_complete()
