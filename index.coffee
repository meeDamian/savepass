#!/usr/bin/env coffee
'use strict'

inquirer = require 'inquirer'
{exec}   = require 'child_process'
async    = require 'async'
chalk    = require 'chalk'
meow     = require 'meow'
path     = require 'path'
uuid     = require 'node-uuid'
fs       = require 'fs-extra'


#
# constants
#
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

RE_FILELDS = new RegExp '<(' + (af for af of AVAILABLE_FIELDS).join('|') + ')>', 'g'


#
# log helpers
#
log = => console.log.apply @, arguments if DEBUG
print = => console.log.apply @, arguments
toJson = (obj) -> JSON.stringify obj, null, 2
logJson = (obj) -> log toJson obj
pad = (text) ->
  [].concat '',
    text.split '\n'
    ''
    ''...
  .join '\n  '

#
# utilities
#
_getHomeDir = -> process.env.HOME or process.env.USERPROFILE

getConfigPath = (dir='savepass', file='config.json') ->
  path.resolve [
    _getHomeDir()
    '.config'
    dir
    file
  ]...

getTemplatePath = (templateName='') ->
  path.resolve [
    __dirname
    'templates'
    templateName
  ]...

getOutputPath = ({path:p}, fileName='') ->
  path.resolve [
    p?.replace(/^~/, _getHomeDir()) ? OUTPUTS_DIR
    fileName
  ]...

cli = meow
  help: [
    'Usage: ' + chalk.bold 'savepass <command>'
    ''
    'where <command> is one of:'
    '    add, new, encrypt, list, ls, getAll'
    '    get, decrypt, remove, rm'
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
    chalk.bold('savepass get') + '/' + chalk.bold('rm') + ' flags:'
    '    ' + chalk.bold('--file') + '=<file>'
    '        Specify file to be acted on. If there\'s no direct match,'
    '        param will be used as a filter.'
    ''
    'Specify configs in the json-formatted file:'
    '    ' + getConfigPath()
  ].join '\n'

DEBUG = !!cli.flags.debug


prompt = (obj) ->                   new Promise (resolve, reject) ->
  inquirer.prompt obj, resolve

cache = (content, name) ->          new Promise (resolve, reject) ->
  name = (if name then name + '.' else '') + uuid.v4() + '.bak.enc'
  tmpPath = path.resolve getConfigPath(null, 'cache'), name
  log "#{name} caching…"
  fs.outputFile tmpPath, content, (err) ->
    if err
      reject err
      return

    resolve name

getConfig = ->                      new Promise (resolve, reject) ->
  fs.readJson getConfigPath(), (err, data) ->
    if err and err.code is 'ENOENT'
      log 'creating config file...'
      fs.outputJson err.path, DEFAULT_CONFIG, (err) ->
        log 'config (new):', toJson DEFAULT_CONFIG
        resolve DEFAULT_CONFIG
      return

    log 'config (file):', toJson data
    resolve data

getKeybaseMe = ->                   new Promise (resolve, reject) ->
  fs.readJson getConfigPath('keybase'), (err, data) ->
    if err
      reject err
      return

    log 'keybase own config (file):', toJson data
    resolve data.user.name

getKeybaseUser = ->                 new Promise (resolve, reject) ->
  if cli.flags.keybaseUser
    resolve cli.flags.keybaseUser
    return

  resolve getKeybaseMe()

keybaseVerify = ([encText, me]) ->  new Promise (resolve, reject) ->
  cmd = [
    'keybase --log-format=plain pgp verify'
    "-S #{me}"
    "-m '#{encText}'"
  ].join ' '

  log 'keybase(verify):', chalk.white cmd

  exec cmd, (err, stdout, stderr) ->
    if err
      reject err
      return

    log stderr

    isVerified = -1 isnt stderr.indexOf "Signature verified. Signed by #{me}"
    resolve {isVerified, encText}

keybaseEncrypt = ({user, text}) ->  new Promise (resolve, reject) ->
  cmd = [
      'keybase pgp encrypt'
      '-s'
      '-y'
      "-m '#{text}'"
      user
    ].join ' '

  log 'keybase(encrypt):', chalk.white cmd

  exec cmd, (err, encText, stderr) ->
    if err
      reject err
      return

    print pad stderr
    cache(encText).then (name) -> log "#{name} cached."

    resolve encText

keybaseDecrypt = (file) ->          new Promise (resolve, reject) ->
  cmd = [
    'keybase --log-format=plain pgp decrypt'
    "-i '#{file}'"
  ].join ' '

  log 'keybase(decrypt):', chalk.white cmd

  exec cmd, (err, something, stderr) ->
    if err
      reject err
      return

    if -1 != stderr.indexOf '[ERRO]'
      reject stderr
      return

    # additional Keybase info
    log pad stderr

    resolve something

getTemplate = (name) ->             new Promise (resolve, reject) ->
  locPath = getTemplatePath name
  fs.readFile locPath, encoding:'utf8', (err, fileContent) ->
    if err
      reject err
      return

    resolve
      file: locPath
      fileName: name
      fileContent: fileContent
      fields: m[1] while m = RE_FILELDS.exec fileContent
      name:
        name.replace /\.temp$/, ''
          .replace /-/g, ' '
          .split ' '
          .map (word) ->
            word.charAt(0).toUpperCase() +
            word.substr 1
          .join ' '

getTemplates = ->                   new Promise (resolve, reject) ->
  fs.readdir getTemplatePath(), (err, files) ->
    if err
      log 'no templates available', toJson err
      reject err
      return

    Promise.all(files.map getTemplate)
      .then resolve
      .catch reject

getSavedFiles = (config) ->         new Promise (resolve, reject) ->
  fs.readdir getOutputPath(config), (err, files) ->
    if err
      log "error reading dir: #{getOutputPath config}", toJson err
      reject err
      return

    fileList = files.filter (fileName) -> new RegExp('.enc.txt$').test fileName
    log 'Saved files:', toJson fileList
    resolve fileList

formatSavedFiles = (files, opts = {}) ->
  opts.showRaw ?= true

  files
    .map (fileName) ->
      l = ['']
      l.push chalk.green '*' if opts.showRaw
      l.push chalk.bold(
        fileName
          .replace new RegExp(opts.ext + '$'), ''
          .replace /[-_]/g, ' '
        ), chalk.dim "(#{fileName})"
      l = l.join ' '

      if opts.showRaw
        return l

      name: l
      value: fileName


switch cli.input[0]
  when 'add', 'new', 'encrypt', undefined
    getTemplates()
      .catch (err) -> log err

      # step 1: AKA choose template
      .then step1 = (templates) ->
        userFilter = cli.flags.template?.toLowerCase()

        matching = templates.filter (t) ->
          -1 < t.fileName.indexOf userFilter

        if matching.length is 1
          return matching[0]

        if matching.length is 0
          matching = templates
          if userFilter
            print chalk.red 'No match found.\n'

        choices = matching.map (v, i) ->
          name: v.name
          value: i

        prompt
          type: 'list'
          name: 'type'
          message: 'Which template do you want to use?'
          choices: choices
          filter: (i) -> matching[i]
        .then (answer) ->
          return answer.type

      # step 2: AKA get ALL THE DATA
      .then step2 = (chosenTemplate) ->
        log 'chosen template:', toJson chosenTemplate

        getQuestionFor = (fieldType) ->
          base = AVAILABLE_FIELDS[fieldType]

          type: base.type ? 'input'
          name: fieldType
          message: base.msg ? 'Input your ' + fieldType

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

          # ignore explicitly disabled fields
          else if encryptables[field] in ['null', 'false']
            encryptables[field] = null

        log 'encryptables (CLI)', toJson encryptables
        log 'questions', toJson questions

        prompt questions
          .then (answers) ->
            log 'answers', toJson answers

            # merge CLI and prompts
            for a of encryptables when answers[a] and answers[a] isnt ''
              encryptables[a] = answers[a]

            log 'encryptables (ALL)', toJson encryptables

            return {
              template: chosenTemplate.fileContent
              encryptables
            }

      # step 3: AKA fill template with data
      .then step3 = ({template, encryptables: data}) ->
        log 'Template and data before merge:\n', template, toJson data

        for key, val of data
          template = template.replace "<#{key}>", val ? ''

        prompt
          type: 'confirm'
          name: 'proceed'
          message: [ 'The following content will be encrypted and saved:'
            ''
            template
            'Do you want to proceed?'
          ].join '\n'
        .then (answer) ->
          unless answer.proceed
            throw 'silent'

          return {
            name: data.website
            text: template
          }

      # NOTE: requires internet!
      # step 4: AKA keybase encrypt and sign
      .then step4 = ({name, text}) ->
        getKeybaseUser()
          .then (user) ->
            print chalk.white('Encrypting and signing for:'), chalk.green user

            Promise.all [
              keybaseEncrypt {user, text}
              getKeybaseMe()
            ]
            .then keybaseVerify
            .then ({isVerified, encText}) ->
              print chalk.white('Signature verification:'), if isVerified then chalk.green('PASSED') else chalk.red 'FAILED'

              {name, encText}

      # step 5: AKA get file name and path
      .then step5 = ({name, encText}) ->
        log 'file name:', name

        getConfig().then (config) ->
          fullPath = undefined

          question =
            name: 'fileName'
            message: 'How do you want to name the file?'
          if name
            question.default = name.replace '.', '-'

          confirmation =
            name: 'confirm'
            type: 'confirm'
            message: (prevAnswer) ->
              fullPath = getOutputPath config, prevAnswer.fileName + config.extensions
              [
                'File will be saved as:'
                ' ' + fullPath
              ].join '\n'

          askFileName = ->
            prompt [question, confirmation]
              .then (answers) ->
                unless answers.confirm
                  throw 'retry'

                {fullPath, encText}

              .catch (err) -> askFileName()

          askFileName()

      # step6: AKA save to a file
      .then step6 = ({fullPath, encText}) ->
        print 'saving…'

        fs.outputFile fullPath, encText, (err) ->
          if err
            print chalk.red('FAIL'), err
            return

          print chalk.green 'Success!'

      .catch (err) ->
        if err isnt 'silent'
          console.log err

  when 'ls', 'list', 'getAll'
    getConfig().then (config) ->
      getSavedFiles(config).then (fileList) ->
        print "Your encrypted files (from #{chalk.bold getOutputPath config}):\n"
        print formatSavedFiles(fileList, ext: config.extensions).join '\n'

      .catch (err) ->
        console.error 'Error loading files...', err

  when 'get', 'decrypt'
    getConfig().then (config) ->
      getSavedFiles(config).then (fileList) ->
        userFilter = cli.flags.file?.toLowerCase()

        matching = fileList.filter (t) ->
          -1 < t.replace(config.extensions, '').toLowerCase().indexOf userFilter

        if matching.length is 1
          return matching[0]

        if matching.length is 0
          matching = fileList
          if userFilter
            print chalk.red 'No match found.\n'

        prompt
          type: 'list'
          name: 'fileName'
          message: 'Which file do you want to decrypt?'
          choices: formatSavedFiles matching,
            showRaw: false
            ext: config.extensions
        .then (answer) -> answer.fileName

      .then (fileName) ->
        fullPath = getOutputPath config, fileName
        print 'Decrypting', chalk.white(fullPath) + '…'
        fullPath

      .then keybaseDecrypt
      .then pad
      .then print

      .catch (err) ->
        console.log err

  when 'rm', 'remove'
    getConfig().then (config) ->
      getSavedFiles(config).then (fileList) ->
        userFilter = cli.flags.file?.toLowerCase()

        matching = fileList.filter (t) ->
          -1 < t.replace(config.extensions, '').toLowerCase().indexOf userFilter

        if matching.length is 1
          return matching

        if matching.length is 0
          matching = fileList
          if userFilter
            print chalk.red 'No match found.\n'

        prompt
          type: 'checkbox'
          name: 'fileNames'
          message: 'Which files do you want to remove?'
          choices: formatSavedFiles matching,
            showRaw: false
            ext: config.extensions
        .then (answer) ->
          answer.fileNames

      # confirm removal
      .then (fileNames) ->
        quantity = if fileNames.length is 1 then 'This file' else 'Those files'

        msg = [
          "#{quantity} will be PERMANENTLY removed (from #{getOutputPath(config)}):"
          formatSavedFiles(fileNames).join '\n'
          ''
          'Are you sure?'
        ].join '\n'

        prompt
          type: 'confirm'
          message: msg
          name: 'confirmRemoval'
          default: false

        .then (answer) ->
          unless answer.confirmRemoval
            throw 'Removal cancelled.'

          return fileNames

      # Expand file names to full paths
      .then (confirmedFileList) ->
        confirmedFileList.map (file) ->
          getOutputPath config, file

      # Remove all files
      .then (fullFilePaths) ->
        log chalk.red('Permanently deleting'), toJson fullFilePaths

        async.map fullFilePaths, fs.unlink, (err) ->
          if err
            throw err

          print chalk.green 'deleted.'

      .catch (err) ->
        print chalk.red pad err

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
