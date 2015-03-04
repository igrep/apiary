#!/bin/bash

dir=$(cd `dirname $0`; pwd)
password=`cat password`

cd $dir
uglifyjs static/api-documentation.js > static/api-documentation.min.js
uglifycss static/api-documentation.css > static/api-documentation.min.css

for pkg in . `cat submodules`; do
  echo $pkg
  cd $dir/$pkg
  cabal clean
  file=`cabal sdist | awk '{LL = $4}END{print LL}'`
  sleep 10
  cabal upload $file
  cd ..
done