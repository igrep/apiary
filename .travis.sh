#!/usr/bin/env bash -eu

printHeader () {
  echo "################################################################################"
  echo "                                   " $1
  echo "################################################################################"
}

printHeader apiary
cabal configure --enable-tests
cabal test
cabal install

for path in apiary-cookie apiary-persistent apiary-websockets apiary-clientsession; do
  cd $path
  printHeader $path
  cabal configure --enable-tests
  cabal test
  cabal install
  cd ..
done
