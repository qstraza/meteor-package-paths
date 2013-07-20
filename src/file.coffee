fs     = require 'fs'
fsPath = require 'path'
wrench = require 'wrench'

CLIENT = 'client'
SERVER = 'server'
SHARED = 'shared'

REQUIRE           = 'require'
REQUIRE_TREE      = 'require_tree'
REQUIRE_DIRECTORY = 'require_directory'


###
Represents a single file.
###
module.exports = class File
  constructor: (@path) ->
    # Setup initial conditions.
    @exists = fs.existsSync(path)
    if @exists
      @isFile = fs.statSync(path).isFile()

    # Store values.
    @dir       = fsPath.dirname(@path)
    @extension = fsPath.extname(@path)
    @domain    = executionDomain(@)


  isValid: -> @exists and @isFile
  toString: -> @path

  ###
  Retrieves an array of file directives from the initial lines that start
  with the directive comment, eg:
    //= (javascript)
    #=  (coffeescript)

    Directives:
      require
      require_tree
      require_directory

  ###
  directives: ->
    # Setup initial conditions.
    commentPrefix = switch @extension
                      when '.js' then '//='
                      when '.coffee' then '#='
    return unless commentPrefix

    # Read the directive lines into an array.
    reader = new wrench.LineReader(@path)
    readLine = ->
      if reader.hasNextLine()
        line = reader.getNextLine()
        return line if line.startsWith(commentPrefix)

    result = []
    while line = readLine()
      line = line.remove( new RegExp("^#{ commentPrefix }") )
      line = line.trim()
      unless line.isBlank()
        directive = new Directive(@, line)
        result.push(directive) if directive.isValid

    # Finish up.
    reader.close()
    result



  ###
  Retrieves an ordered array of prerequsite files that need to be loaded
  before this file.
  ###
  prereqs: ->
    # Setup initial conditions.
    result = []
    directives = @directives()

    for directive in directives
      for file in directive.toFiles()
        alreadyAdded = result.any (item) -> item.path is file.path
        unless alreadyAdded
          result.push(file)

    # Finish up.
    result



###
Generates the ordered list of files for the entire hierarchy under the given directory (deep).
@param dir: The root directory to retrieve the file listing from.
###
File.tree = (dir) -> toOrderedFiles(readdir(dir, true))

###
Generates the ordered list of files under the given directory (shallow).
@param dir: The root directory to retrieve the file listing from.
###
File.directory = (dir) -> toOrderedFiles(readdir(dir, false))






# --------------------------------------------------------------------------




###
Represents a single comment directive within a file.
###
class Directive
  constructor: (@file, @text) ->
    # Setup initial conditions.
    parts = @text.split(' ')
    @type = parts[0]
    @path = parts[1] ? ''

    # Ensure the directive is valid.
    @isValid = [REQUIRE, REQUIRE_TREE, REQUIRE_DIRECTORY].any (item) => item is @type
    @isValid = false if @path.isBlank()

    # Format the path.
    if @isValid and @path.startsWith('.')
      @path = fsPath.resolve("#{ @file.dir }/#{ @path }")


  toString: -> @text


  toFiles: ->
    # Setup initial conditions.
    result = []
    return result unless @isValid

    add = (file) =>
        # Ensure the file can be added.
        throw new Error("The file for the directive [#{ @text }] does not exist [Path: #{ file.path }].") unless file.exists
        throw new Error("The file for the directive [#{ @text }] is not valid.") unless file.isValid()
        if file.domain isnt @file.domain
          throw new Error("The file for the directive [#{ @text }] is in the exeuction domain '#{ file.domain }' and cannot be added to the execution domain '#{ @file.domain }' of the file [#{ @file.path }]")

        # Add any pre-requisites first.
        prereqs = file.prereqs()
        if prereqs.length > 0
          add(prereqFile) for prereqFile in prereqs

        # Add the given file.
        result.push(file)


    switch @type
      when REQUIRE then add(new File(@path))


      # when REQUIRE_TREE
      #   result = File.tree(@path)
    #   when 'require'



    # Finish up.
    result







# PRIVATE --------------------------------------------------------------------------




executionDomain = (file) ->
  # Find the last reference within the path to an execution domain.
  for part in file.path.split('/').reverse()
    return CLIENT if part is CLIENT
    return SERVER if part is SERVER
    return SHARED if part is SHARED

  SHARED # No execution domain found - default to 'shared'.



readdir = (dir, deep) ->
  dir = fsPath.resolve(dir)
  if deep
    paths = wrench.readdirSyncRecursive(dir)
  else
    paths = fs.readdirSync(dir)
  paths = paths.map (path) -> "#{ dir }/#{ path }"
  paths



toOrderedFiles = (paths) ->
  paths = paths.filter (path) -> not fsPath.extname(path).isBlank() # Remove folder-only paths.
  files = paths.map (path) -> new File(path)

  # Partition paths into their execution domains.
  byDomain = (domain) -> files.filter (file) -> file.domain is domain
  result =
    client: byDomain('client')
    server: byDomain('server')
    shared: byDomain('shared')

  # Process paths.
  process = (files) ->
    files = sortDeepest(files)
    files = withPrereqs(files)
    files

  for key, files of result
    result[key] = process(files)

  # Finish up.
  result



sortDeepest = (files) ->
  # Organize files by folder.
  byFolder = {}
  for file in files
    byFolder[file.dir] ?= []
    byFolder[file.dir].push( file )

  # Convert to array.
  folders = []
  for key, value of byFolder
    folders.push({ dir:key, files:value })

  # Sort by depth.
  fnSort = (item) -> item.dir.split('/').length
  folders = folders.sortBy(fnSort, desc:true)
  folders = folders.sortBy(fnSort, desc:true)

  # Flatten to array.
  result = []
  for item in folders
    for file in item.files
      result.push file

  # Finish up.
  result



