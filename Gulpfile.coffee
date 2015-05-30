gulp  = require 'gulp'
del   = require 'del'
g     = require('gulp-load-plugins')()


gulp.task 'bump', g.shell.task ['npm version patch']

gulp.task 'compile', ['javascriptize'], ->
  gulp.src ['*.coffee', '!Gulpfile.coffee']
    .pipe g.coffee(bare: true).on 'error', g.util?.log
    .pipe g.insert.prepend '#!/usr/bin/env node\n'
    .pipe gulp.dest '.'

gulp.task 'javascriptize', ['bump'], ->
  gulp.src 'package.json'
    .pipe gulp.dest 'tmp'
    .pipe g.jsonEditor main: 'index.js'
    .pipe g.jsonEditor scripts: start: 'node index.js'
    .pipe g.jsonEditor bin: savepass: './index.js'
    .pipe gulp.dest '.'

gulp.task 'prepublish', ['compile']


gulp.task 'postpublish', ->
  gulp.src 'tmp/package.json'
    .pipe gulp.dest '.'

  del ['*.js', 'tmp'], (err, paths) ->
    f = paths.map (f) -> ' * ' + f
      .join '\n'

    if f
      console.log 'removed build files:'
      console.log f

gulp.task 'publish', ['prepublish'], g.shell.task [
    'npm publish'
  ]


gulp.task 'lint', ->
  gulp.src '**.coffee'
    .pipe g.coffeelint()
    .pipe g.coffeelint.reporter()


gulp.task 'test', ['lint'], ->
  console.log 'tests go here'
