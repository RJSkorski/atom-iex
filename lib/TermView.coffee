util       = require 'util'
path       = require 'path'
os         = require 'os'
fs         = require 'fs-plus'

debounce   = require 'debounce'
Terminal   = require 'atom-term.js'

keypather  = do require 'keypather'

{$, View, Task} = require 'atom'

last = (str)-> str[str.length-1]

renderTemplate = (template, data)->
  vars = Object.keys data
  vars.reduce (_template, key)->
    _template.split(///\{\{\s*#{key}\s*\}\}///)
      .join data[key]
  , template.toString()

class TermView extends View

  @content: ->
    @div class: 'iex2'

  constructor: (@opts={})->
    console.log "CONS"
    opts.shell = process.env.SHELL or 'bash'
    opts.shellArguments or= ''

    editorPath = keypather.get atom, 'workspace.getEditorViews[0].getEditor().getPath()'
    opts.cwd = opts.cwd or atom.project.getPath() or editorPath or process.env.HOME
    console.log "CONS2"
    super

  forkPtyProcess: (args=[])->
    console.log
    processPath = require.resolve './pty'
    path = atom.project.getPath() ? '~'
    Task.once processPath, fs.absolute(path), args

  initialize: (@state)->
    {cols, rows} = @getDimensions()
    {cwd, shell, shellArguments, runCommand, colors, cursorBlink, scrollback} = @opts
    args = shellArguments.split(/\s+/g).filter (arg)-> arg
    console.log "INIT"
    @ptyProcess = @forkPtyProcess args
    @ptyProcess.on 'iex:data', (data) => @term.write data
    @ptyProcess.on 'iex:exit', (data) => @destroy()

    colorsArray = (colorCode for colorName, colorCode of colors)
    @term = term = new Terminal {
      useStyle: no
      screenKeys: no
      colors: colorsArray
      cursorBlink, scrollback, cols, rows
    }

    term.end = => @destroy()

    term.on "data", (data)=> @input data
    term.open this.get(0)

    @input "#{runCommand}#{os.EOL}" if runCommand
    term.focus()
    console.log "INIT2"
    @attachEvents()
    @resizeToPane()
    console.log "INIT3"

  input: (data) ->
    @ptyProcess.send event: 'input', text: data

  resize: (cols, rows) ->
    @ptyProcess.send {event: 'resize', rows, cols}

  titleVars: ->
    bashName: last @opts.shell.split '/'
    hostName: os.hostname()
    platform: process.platform
    home    : process.env.HOME

  getTitle: ->
    @vars = @titleVars()
    titleTemplate = @opts.titleTemplate or "({{ bashName }})"
    renderTemplate titleTemplate, @vars

  resizeToPane: ->
    {cols, rows} = @getDimensions()
    return unless cols > 0 and rows > 0
    return unless @term
    return if @term.rows is rows and @term.cols is cols

    @resize cols, rows
    @term.resize cols, rows
    atom.workspaceView.getActivePaneView().css overflow: 'visible'

  attachEvents: ->
    console.log "ATTACHING EVENTS"
    @resizeToPane = @resizeToPane.bind this
    @attachResizeEvents()
    @command "iex:paste", => @paste()
    console.log "DONE ATTACHING EVENTS"

  paste: ->
    @input atom.clipboard.read()

  attachResizeEvents: ->
    setTimeout (=>  @resizeToPane()), 10
    @on 'focus', @focus
    $(window).on 'resize', => @resizeToPane()

  detachResizeEvents: ->
    @off 'focus', @focus
    $(window).off 'resize'

  focus: ->
    @resizeToPane()
    @focusTerm()
    super

  focusTerm: ->
    @term.element.focus()
    @term.focus()


  getDimensions: ->
    fakeCol = $("<span id='colSize'>&nbsp;</span>").css visibility: 'hidden'
    if @term
      @find('.terminal').append fakeCol
      fakeCol = @find(".terminal span#colSize")
      cols = Math.floor (@width() / fakeCol.width()) or 9
      rows = Math.floor (@height() / fakeCol.height()) or 16
      fakeCol.remove()
    else
      cols = Math.floor @width() / 7
      rows = Math.floor @height() / 14

    {cols, rows}

  destroy: ->
    @detachResizeEvents()
    @ptyProcess.terminate()
    @term.destroy()
    parentPane = atom.workspace.getActivePane()
    if parentPane.activeItem is this
      parentPane.removeItem parentPane.activeItem
    @detach()


module.exports = TermView
