class ner_complete extends AnnotationIteration

  _this = undefined
  tokensQuery = '.interfaces-staging >:not(.template) .paragraph-container .token'

  # uncomment to overwrite interface registration at AnnotationLifecylce
  constructor: ->
    _this = this
    this.$tokens = $(tokensQuery)
    this.tokens = []
    this.selectedTokenIndex = -1
    this.knownKeys = [8, 9, 16, 37, 39, 49, 50, 106, 107]
    this.keyMap = []

    # iterate over all tokens and save them in an array
    this.initTokens()

    $(document).keydown (e) ->
      returnStatement = true
      returnStatement = false if _this.knownKeys.indexOf(e.keyCode) >= 0

      return returnStatement unless _this.keyMap.indexOf(e.keyCode) == -1
      _this.keyMap.push(e.keyCode)
      _this.actionFromKeyEvent()
      return returnStatement

    $(document).keyup (e) ->
      keyMapIndex = _this.keyMap.indexOf(e.keyCode)
      _this.keyMap.splice(keyMapIndex)

    this.$tokens.click ->
      $clickedToken = $(this)
      tokenIndex = $clickedToken.data('token-id')

      # handle the selection of a known token
      if tokenIndex >= 0
        _this.selectChunkWithTokenIndex(tokenIndex)
      else
        jQueryIndex = $clickedToken.index(tokensQuery)
        _this.addNewToken($clickedToken, jQueryIndex)

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

  actionFromKeyEvent: ->
    return if this.selectedTokenIndex < 0

    keyIsPressed = (keyId) ->
      _this.keyMap.indexOf(keyId) >= 0

    # backspace
    if keyIsPressed(8)
      _this.removeCurrentChunk()

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
      _this.saveAnnotation() if keyIsPressed(106) # key 'J'
      _this.skip() if keyIsPressed(107) # key 'K'

  addTokenToChunk: (side) ->
    mostOuterTokenListIndex = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, side)
    mostOuterToken = this.tokens[mostOuterTokenListIndex]
    kind = mostOuterToken.kind
    targetIndex = if side == 'left' then mostOuterTokenListIndex - 1 else mostOuterTokenListIndex + 1
    return if targetIndex < 0 || targetIndex >= this.$tokens.length

    mostOuterToken.$token.removeClass("#{side}-end")
    $token = $(this.$tokens.get(targetIndex))
    $token.addClass("selected #{side}-end")

    if side == 'left'
      _this.addTokenToList($token, kind, targetIndex, -1)
      mostOuterToken.leftSiblingIndex = targetIndex
      this.tokens[targetIndex].rightSiblingIndex = mostOuterTokenListIndex

    else if side == 'right'
      _this.addTokenToList($token, kind, targetIndex, mostOuterTokenListIndex)
      mostOuterToken.rightSiblingIndex = targetIndex
      this.tokens[targetIndex].leftSiblingIndex = mostOuterTokenListIndex

  addNewToken: ($token, index) ->
    _this.addTokenToList($token, 'PER', index, -1)
    $token.addClass('left-end')
    $token.addClass('right-end')
    this.changeTokenState(this.selectedTokenIndex, false)
    this.selectedTokenIndex = index
    this.changeTokenState(this.selectedTokenIndex, true)

  removeTokenFromChunk: (side) ->
    mostOuterTokenListIndex = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, side)
    mostOuterToken = this.tokens[mostOuterTokenListIndex]
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
    this.selectedTokenIndex = siblingIndex if this.selectedTokenIndex == mostOuterTokenListIndex

  removeCurrentChunk: ->
    mostOuterTokenListIndex = this.getMostOuterTokenIndexFromChunk(this.selectedTokenIndex, 'left')
    modifier = (token, selected) ->
      token.$token.removeClass('PER COM left-end right-end selected')
      token.$token.data('token-id', -1)
      if token.leftSiblingIndex >= 0
        leftSibling = _this.tokens[token.leftSiblingIndex]
        leftSibling.rightSiblingIndex = -1
      token.leftSiblingIndex = -1
    this.tokenIterator(mostOuterTokenListIndex, modifier, false, false, true)

  selectNextChunk: (side) ->
    nextChunkId = this.findNextChunkIndex(this.selectedTokenIndex, side)
    this.selectChunkWithTokenIndex(nextChunkId)

  findNextChunkIndex: (startIndex, side) ->
    if this.tokens[startIndex]
      mostOuterTokenListIndex = this.getMostOuterTokenIndexFromChunk(startIndex, side)
      queryString = ":gt(#{mostOuterTokenListIndex}).left-end:first" if side == 'right'
      queryString = ":lt(#{mostOuterTokenListIndex}).right-end:last" if side == 'left'
      nextChunkId = $("#{tokensQuery}#{queryString}").data('token-id')

    unless nextChunkId
      queryString = "#{tokensQuery}.left-end:first" if side == 'right'
      queryString = "#{tokensQuery}.left-end:last" if side == 'left'
      nextChunkId = $(queryString).data('token-id')

    return nextChunkId

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

    $paragraphs.each (paragraphIndex, paragraphElement) ->
      payload['content'].push(new Array())
      $('.sentence', $(paragraphElement)).each (sentenceIndex, sentenceElement) ->
        payload['content'][paragraphIndex].push(new Array())
        $('.token', $(sentenceElement)).each (tokenIndex, tokenElement) ->
          $token = $(tokenElement)
          tokenHash = {
            term: $token.html().replace(/^\s+|\s+$/g, '')
          }

          tokenId = $token.data('token-id')
          if tokenId >= 0 && _this.tokenSkipCount == 0
            _this.setCurrentAnnotationLength(tokenId)
            _this.tokenSkipCount = _this.currentAnnotationLength

            tokenHash['annotation'] = {
              label: _this.tokens[tokenId].kind,
              length: _this.currentAnnotationLength
            }

          else if _this.tokenSkipCount > 0
            _this.tokenSkipCount = _this.tokenSkipCount - 1

          payload['content'][paragraphIndex][sentenceIndex].push(tokenHash)

    this.saveChanges(payload)

window.ner_complete = new ner_complete()