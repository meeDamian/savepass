#!/usr/bin/env coffee
'use strict'

inquirer  = require 'inquirer'
{exec}    = require 'child_process'
async     = require 'async'
chalk     = require 'chalk'
meow      = require 'meow'
path      = require 'path'
fs        = require 'fs-extra'


#
# constants
#
DEBUG = no

TEMPLATES_DIR = 'templates'
OUTPUTS_DIR = 'outputs'
DEFAULT_CONFIG =
  path: OUTPUTS_DIR
  extensions: '.enc.txt'

AVAILABLE_FIELDS =
  name: {}
  website: {}
  login: {}
  password: type: 'password'
  email: {}
  seed: msg: 'Input 2FA seed'

#
# log helpers
#
log = => console.log.apply @, arguments if DEBUG
toJson = (obj) -> JSON.stringify obj, null, '  '
logJson = (obj) -> log toJson obj

#
# utilities
#
getHomeDir = -> process.env.HOME or process.env.USERPROFILE
getConfigPath = (name = 'savepass') -> path.join getHomeDir(), "/.config/#{name}/config.json"
getOutputDir = ->
  path.resolve unless config.path then OUTPUTS_DIR else config.path.replace /^~/, getHomeDir()

getFullFilePath = (fileName) -> path.resolve getOutputDir(), fileName


getQuestionFor = (fieldType) ->
  base = AVAILABLE_FIELDS[fieldType]

  type: base.type ? 'input'
  name: fieldType
  message: base.msg ? 'Input your ' + fieldType

getChoicesFrom = (templates) ->
  templates.map (v, i) ->
    name: v.name
    value: i

getFrom = (templates) -> (i) -> templates[i]

getConfig = (name = 'keybase', cb) ->
  if typeof name is 'function'
    [name, cb] = ['savepass', name]

  else if name is 'self'
    name = 'savepass'

  fs.readJson getConfigPath(name), cb


config = {}
readOwnConfig = (next) ->
  getConfig (err, data) ->
    if err and err.code is 'ENOENT'
      log 'creating config file...'

      config = DEFAULT_CONFIG

      log 'config (new):', toJson config

      fs.outputJson err.path, config, next

    else
      config = data
      log 'config (file):', toJson config
      next()

getExtension = ->
  config.extensions or DEFAULT_CONFIG.extensions

templates = []

filterTemplates = (filter) ->
  templates.filter (t) -> -1 < t.fileName.indexOf filter

# read templates from `templates` dir
readTemplates = (next) ->
  templatesDir = path.resolve __dirname, TEMPLATES_DIR

  readTemplate = (template, next) ->
    tempPath = path.resolve templatesDir, template

    fs.readFile tempPath, encoding: 'utf8', (err, fileContent) ->
      if err
        next err
        return

      re = new RegExp('<(' + (af for af of AVAILABLE_FIELDS).join('|') + ')>', 'g')

      templates.push
        file: tempPath
        fileName: template
        fileContent: fileContent
        fields: m[1] while m = re.exec fileContent
        name:
          template.replace /\.temp$/, ''
            .replace /-/g, ' '
            .split ' '
            .map (word) ->
              word.charAt(0).toUpperCase() +
              word.substr 1
            .join ' '

      next()

  fs.readdir templatesDir, (err, files) ->
    if err
      console.error 'not even directory for templates exist.', toJson err
      return

    async.each files, readTemplate, (err) ->
      if err
        console.error 'reading template file failed... apparently', err
        return

      log "#{templates.length} templates read:", templates.map (t) -> t.fileName
      next()

getEncryptedFilesList = (cb) ->
  fs.readdir getOutputDir(), (err, files) ->
    if err
      console.error err
      cb err

    fileList = files.filter (fileName) -> new RegExp('.enc.txt$').test fileName
    log fileList

    cb null, fileList

colorFilesList = (files, opts={}) ->
  opts.leadingAsterix ?= true
  opts.returnAsKeyValue ?= false

  files
    .map (fileName) ->
      l = ['']
      l.push chalk.green '*' if opts.leadingAsterix
      l.push chalk.bold(
          fileName
            .replace new RegExp(getExtension() + '$'), ''
            .replace /[-_]/g, ' '
        ), chalk.dim "(#{fileName})"
      l = l.join ' '

      return l unless opts.returnAsKeyValue

      name: l
      value: fileName


cli = meow
  help: [
    'Usage: ' + chalk.bold 'savepass <command>'
    ''
    'where <command> is one of:'
    '    add, new, list, ls, remove, rm'
    ''
    'Example Usage:'
    '    savepass add [OPTIONAL <flags>]'
    '    savepass --debug ls'
    '    savepass rm --file=myBank'
    ''
    'Global flags:'
    '    ' + chalk.bold('--debug')
    '        Enable debug output.'
    ''
    chalk.bold('savepass add') + ' flags:'
    '    ' + chalk.bold('--template') + '=<templateName>'
    '        Specify template name to be used. Available templates can be'
    '        found in `templates/` folder.'
    '    ' + chalk.bold('--keybase-user') + '=<keybaseUsername>'
    '        Encrypt output file for a different user then the one logged in.'
    '    ' + (chalk.bold("--#{f}") for f of AVAILABLE_FIELDS).join ', '
    '        Pass values from CLI or disable by passing null or false. '
    '        ' + chalk.red('NOTE: ') + chalk.bold('--password') + ' flag can only be disabled'
    ''
    'Specify configs in the json-formatted file:'
    '    ' + getConfigPath()
  ].join '\n'

DEBUG = yes if cli.flags.debug

log 'cli flags:', cli.input, toJson cli.flags


async.parallel [
  readTemplates
  readOwnConfig

], (err) ->
  if err
    console.error err
    return

  switch cli.input[0]
    when 'add', 'new', undefined

      # AKA save to a file
      step6 = (path, content) ->
        console.log 'saving...'

        fs.outputFile path, content, (err) ->
          return console.error err if err

          console.log 'success!'


      # AKA get file name and path
      step5 = (fileName, contents) ->
        log 'file name:', fileName

        q =
          name: 'fileName'
          message: 'How do you want to name the file?'

        q.default = fileName.replace '.', '-' if fileName

        filePath = null

        qs = [
          q
        ,
          name: 'confirm'
          type: 'confirm'
          message: (prevAnswer) ->
            outputDir = getOutputDir()

            log 'Output files dir:', outputDir

            filePath = path.resolve outputDir, prevAnswer.fileName + (config.extensions or DEFAULT_CONFIG.extensions)

            [
              'File will be saved as:'
              ' ' + filePath
            ].join '\n'
        ]

        inquirer.prompt qs, (answers) ->
          unless answers.confirm
            step5 answers.fileName, contents
            return

          step6 filePath, contents

      # AKA keybase encrypt and sign
      # NOTE: that step requires internet!
      step4 = (name, text) ->
        getKeybaseUser = (cb) ->
          if cli.flags.keybaseUser
            cb cli.flags.keybaseUser
            return

          getConfig 'keybase', (err, data) ->
            cb data.user.name

        getKeybaseUser (keybaseUser) ->
          console.log "Encrypting and signing for: #{keybaseUser}"
          exec [
            'keybase encrypt' # encrypt the message
            '-s' # but also sign
            "-m '#{text}'" # pass the message
            keybaseUser # use my public key

          ].join(' '), (err, stdout, stderr) ->
            if err or stderr
              console.error err if err
              console.error stderr if stderr
              return

            log 'encrypted file:\n', stdout

            step5 name, stdout


      # AKA fill template with data
      step3 = (template, data) ->
        log 'Template and data before merge:\n', template, toJson data

        template = template.replace "<#{key}>", val ? '' for key, val of data

        inquirer.prompt
          type: 'confirm'
          name: 'proceed'
          message: [ 'The following content will be encrypted and saved:'
            ''
            template
            'Do you want to proceed?'
          ].join '\n'

        , (answers) ->
          step4 data.website, template if answers.proceed


      # AKA get ALL THE DATA
      step2 = (chosenTemplate) ->
        log 'chosen template:', toJson chosenTemplate

        # always ask for password - ignore CLI flag
        questions = [
          getQuestionFor 'password'
        ]
        encryptables =
          password: null

        # check for CLI flags
        for field in chosenTemplate.fields when field isnt 'password'
          encryptables[field] = cli.flags[field] ? null

          # if field isn't provided via CLI - ask for it
          unless encryptables[field]
            questions.push getQuestionFor field

          # ignore fields explicitly disabled
          else if encryptables[field] in ['null', 'false']
            encryptables[field] = null

        log 'encryptables (CLI)', toJson encryptables
        log 'questions', toJson questions

        # ask for still missing data
        inquirer.prompt questions, (answers) ->
          log 'answers', toJson answers

          # merge CLI and prompts
          for a of encryptables when answers[a] and answers[a] isnt ''
            encryptables[a] = answers[a]

          log 'encryptables (ALL)', toJson encryptables

          step3 chosenTemplate.fileContent, encryptables


      # AKA choose template
      step1 = (templates) ->
        inquirer.prompt
          type: 'list'
          name: 'type'
          message: 'Which template do you want to use?'
          choices: getChoicesFrom templates
          filter: getFrom templates

        , (answer) -> step2 answer.type


      # step0
      matchingTemplates = filterTemplates cli.flags.template
      switch matchingTemplates.length
        when 0 then step1 templates # no `--templates=?` flag passed
        when 1 then step2 matchingTemplates[0] # exactly one match
        else step1 matchingTemplates # more than one match

    when 'list', 'ls'
      getEncryptedFilesList (err, fileList) ->
        unless err
          fileList = colorFilesList(fileList).join '\n'

        console.log "Your encrypted files (from #{chalk.bold getOutputDir()}):\n"
        console.log fileList

    when 'remove', 'rm'

      remove = (files, cb) ->
        log 'Running REMOVE on: ', toJson files
        async.map files, fs.unlink, cb

      removeFiles = (files) ->
        fullPaths = files.map getFullFilePath

        remove fullPaths, (err) ->
          if err
            console.error 'Bummer, there was an error:', err
            return

          console.log "File#{if fullPaths.length > 1 then 's' else ''} successfully removed."


      askConfirmation = (filesToBeRemoved) ->
        info = if filesToBeRemoved.length is 1 then 'This file' else 'Those files'
        info += " will be PERMANENTLY removed (from #{getOutputDir()}):"

        msg = [
          info
          colorFilesList(filesToBeRemoved).join '\n'
          '\nAre you sure?'
        ].join '\n'

        inquirer.prompt
          type: 'confirm'
          message: msg
          name: 'confirmRemoval'
          default: false

        , (answers) ->
          removeFiles filesToBeRemoved if answers.confirmRemoval


      removable = cli.flags.file
      getEncryptedFilesList (err, files) ->
        unless removable
          inquirer.prompt
            type: 'checkbox'
            name: 'fileNames'
            message: 'Which files do you want to remove?'
            choices: colorFilesList(files, {leadingAsterix: false, returnAsKeyValue: true})

          , (answers) -> askConfirmation answers.fileNames

        else
          file = cli.flags.file
          file += getExtension() unless new RegExp(getExtension() + '$').test file

          unless file in files
            console.error 'Provided file not found in ' # add dir
            return

          askConfirmation [ file ]


###

 file
 login
 email
 password
 website
 2FA
 rule (desc)
 just password(s)

 creds|credentials
 one
 many|multi
 file
 desc

###