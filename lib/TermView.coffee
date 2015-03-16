util        = require 'util'
path        = require 'path'
os          = require 'os'
fs          = require 'fs-plus'
uuid        = require 'uuid'

Terminal    = require 'atom-iex-term.js'

keypather   = do require 'keypather'

{Task, CompositeDisposable} = require 'atom'
{$, View, ScrollView} = require 'atom-space-pen-views'

uuids = []

last = (str)-> str[str.length-1]

generateUUID = ()->
  new_id = uuid.v1().substring(0,4)
  while new_id in uuids
    new_id = uuid.v1().substring(0,4)
  uuids.push new_id
  new_id

getMixFilePath = ()->
  mixPath = null
  for projectPath in atom.project.getPaths()
    do (projectPath) ->
      if projectPath && fs.existsSync(path.join(projectPath, 'mix.exs'))
        mixPath = path.join(projectPath, 'mix.exs')
        return
  mixPath


renderTemplate = (template, data)->
  vars = Object.keys data
  vars.reduce (_template, key)->
    _template.split(///\{\{\s*#{key}\s*\}\}///)
      .join data[key]
  , template.toString()

class TermView extends View

  @content: ->
    @div class: 'iex', click: 'click'

  constructor: (@opts={})->
    opts.shell = process.env.SHELL or 'bash'
    opts.shellArguments or= ''

    editorPath = keypather.get atom, 'workspace.getEditorViews[0].getEditor().getPath()'
    opts.cwd = opts.cwd or atom.project.getPath() or editorPath or process.env.HOME
    super

  forkPtyProcess: (args=[])->
    processPath = require.resolve './pty'
    projectPath = atom.project.getPath() ? '~'
    Task.once processPath, fs.absolute(projectPath), args

  initialize: (@state)->
    iexSrcPath = atom.packages.resolvePackagePath("iex") + "/elixir_src/iex.exs"
    {cols, rows} = @getDimensions()
    {cwd, shell, shellArguments, runCommand, colors, cursorBlink, scrollback} = @opts
    new_id = generateUUID()
    args = ["-c", "iex --sname IEX-" + new_id + " -r " + iexSrcPath]
    mixPath = getMixFilePath()
    # assume mix file is at top level
    if mixPath
      args = ["-c", "iex --sname IEX-" + new_id + " -r " + iexSrcPath + " -S mix"]

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

    term.on "copy", (text)=> @copy(text)

    term.on "data", (data)=> @input data
    term.open this.get(0)

    @input "#{runCommand}#{os.EOL}" if runCommand
    term.focus()
    @attachEvents()
    @resizeToPane()

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

  attachEvents: ->
    @resizeToPane = @resizeToPane.bind this
    @attachResizeEvents()
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register commands
    @subscriptions.add atom.commands.add '.iex', 'iex:paste': => @paste()
    @subscriptions.add atom.commands.add '.iex', 'iex:copy': => @copy()
    atom.workspace.onDidChangeActivePaneItem (item)=> @onActivePaneItemChanged(item)

  click: (evt, element) ->
    @focus()

  paste: ->
    @input atom.clipboard.read()

  copy: ->
    if @term._selected  # term.js visual mode selections
      textarea = @term.getCopyTextarea()
      text = @term.grabText(
        @term._selected.x1, @term._selected.x2,
        @term._selected.y1, @term._selected.y2)
    else # fallback to DOM-based selections
      text = @term.context.getSelection().toString()
      rawText = @term.context.getSelection().toString()
      rawLines = rawText.split(/\r?\n/g)
      lines = rawLines.map (line) ->
        line.replace(/\s/g, " ").trimRight()
      text = lines.join("\n")
    atom.clipboard.write text

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
    #super

  focusTerm: ->
    @term.element.focus()
    @term.focus()

  resizeToPane: ->
    {cols, rows} = @getDimensions()
    return unless cols > 0 and rows > 0
    return unless @term
    return if @term.rows is rows and @term.cols is cols

    @resize cols, rows
    @term.resize cols, rows
    #atom.workspaceView.getActivePaneView().css overflow: 'auto'

  getDimensions: ->
    fakeCol = $("<span id='colSize'>m</span>").css visibility: 'hidden'
    if @term
      @find('.terminal').append fakeCol
      fakeCol = @find(".terminal span#colSize")
      cols = Math.floor (@width() / fakeCol.width()) or 9
      #cols = Math.floor (@width() / 10)  or 9
      rows = (Math.floor (@height() / fakeCol.height()) - 2) or 16
      #rows = Math.floor (@height() / 14)  or 16
      fakeCol.remove()
    else
      cols = Math.floor @width() / 7
      rows = Math.floor @height() / 14

    {cols, rows}

  activate: ->
    @focus

  onActivePaneItemChanged: (activeItem) =>
    if (activeItem == this)
      @focusTerm()

  deactivate: ->
    @subscriptions.dispose()

  destroy: ->
    @detachResizeEvents()
    @ptyProcess.terminate()
    @term.destroy()
    parentPane = atom.workspace.getActivePane()
    if parentPane.activeItem is this
      parentPane.removeItem parentPane.activeItem
    @detach()

module.exports = TermView
