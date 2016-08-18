// ##### Gulp Toolkit for the eScholarship UI Library #####

const gulp = require('gulp');
const gutil = require('gulp-util');
const sass = require('gulp-sass');
const autoprefixer = require('gulp-autoprefixer');
const sourcemaps = require('gulp-sourcemaps');
const browserSync = require('browser-sync');
const del = require('del');
const runSequence = require('run-sequence');
const scsslint = require('gulp-scss-lint');
const postcss = require('gulp-postcss');
const assets = require('postcss-assets');
const source = require('vinyl-source-stream');
const browserify = require('browserify');
const watchify = require('watchify');
const streamify = require('gulp-streamify');
const eslintify = require('eslintify');
const babelify = require('babelify');
const livereload = require('gulp-livereload')
const exec = require('child_process').exec
const spawn = require('child_process').spawn
const wait = require('gulp-wait')
 
// Processes we will start up
var sinatraProc // Main app in Sinatra (Ruby)
var expressProc // Sub-app for isomophic javascript in Express (Node/Javascript)

// Transformations to build bundle.js
gulp.task('browserify', function() {
  var watcher  = watchify(browserify({
    entries: ['app/jsx/app.jsx'],
    debug: true,
    cache: {}, packageCache: {}, fullPaths: true
  }));
  watcher.on('update', function () {
    watcher.bundle()
      .on('error', gutil.log.bind(gutil, 'Browserify Error'))
      .pipe(source('app/js/bundle.js'))
      .pipe(gulp.dest('.'));
    console.log('app/js/bundle.js updated');
  }).transform('babelify', {presets: ['es2015', 'react']})
    .bundle()
    .pipe(source('app/js/bundle.js'))
    .pipe(gulp.dest('.'))
    .on('end', function() { livereload.reload() });
});

// Run the dev process 'gulp':
gulp.task('default', function (callback) {
  runSequence(['browserify', 'watch', 'sinatra'],  // FIXME: add 'express' when we do iso
    callback
  )
})

// Process Sass to CSS, add sourcemaps, autoprefix CSS selectors, optionally Base64 font and image files into CSS, and reload browser:
gulp.task('sass', function() {
  gulp.src('app/scss/**/*.scss')
    .pipe(sourcemaps.init())
    .pipe(sass.sync().on('error', sass.logError))
    .pipe(autoprefixer('last 2 versions'))
    .pipe(postcss([assets({ loadPaths: ['fonts/', 'images/'] })]))
    .pipe(sourcemaps.write('sourcemaps'))
    .pipe(gulp.dest('app/css'))
    .pipe(browserSync.reload({ stream: true }));
})

// Watch sass, html, and js and reload browser if any changes:
gulp.task('watch', ['sass', 'scss-lint'], function() {
  livereload.listen();
  gulp.watch('app/scss/**/*.scss', ['sass']);
  gulp.watch('app/scss/**/*.scss', ['scss-lint']);
  gulp.watch('app/**/*.html', browserSync.reload); 
  gulp.watch('app/js/**/*.js', browserSync.reload); 
  gulp.watch('app/js/bundle.js', browserSync.reload);
});

///////////////////////////////////////////////////////////////////////////////////////////////////
// Fire up the main app in Sinatra (Ruby).
gulp.task('sinatra', function() {
  sinatraProc = spawn('ruby', ['app/escholApp.rb', '-p', '4001'], { stdio: 'inherit' })
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// Fire up the isomorphic sub-app in Node/Express (Javascript)
gulp.task('express', function() {
  //var env = process.env
  //env['NODE_PATH'] = env['CWD']
  expressProc = spawn('node', ['app/escholIso.js'], { stdio: 'inherit' })
  expressProc.on('exit', function() {
    expressProc = null
  })
})

// Delete 'dist' directory at start of build process:
gulp.task('clean', function() {
  return del('dist');
})

// Lint Sass
gulp.task('scss-lint', function() {
  return gulp.src(['app/scss/**/*.scss', '!app/scss/vendor/**/*.scss'])
    .pipe(scsslint({
      'config': 'scss-lint-config.yml' // Settings for linters. See: https://github.com/brigade/scss-lint/tree/master/lib/scss_lint/linter
    }));
});
