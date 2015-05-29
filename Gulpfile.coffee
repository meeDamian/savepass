gulp  = require 'gulp'
g     = require('gulp-load-plugins')()


gulp.task 'lint', ->
  gulp.src '**.coffee'
    .pipe g.coffeelint()
    .pipe g.coffeelint.reporter()


gulp.task 'test', ['lint'], ->
