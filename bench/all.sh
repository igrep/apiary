#!/bin/bash

if [ $# -eq 1 ]; then
  NTHREAD=$1
  MACHINE=`uname -n`
elif [ $# -eq 2 ]; then
  NTHREAD=$1
  MACHINE=$2
else
  NTHREAD=1
  MACHINE=`uname -n`
fi


for PKG in apiary-0.14.0.1 apiary-0.15.0 apiary-0.15.1 Spock-0.6.2.1 scotty-0.8.2; do
  FRAMEWORK=`echo $PKG | awk -F'-' '{print $1}'`
  VERSION=`echo $PKG | awk -F'-' '{print $2}'`

  cabal sandbox hc-pkg unregister $FRAMEWORK
  cabal install ./$PKG
  cabal clean
  cabal configure
  cabal build $FRAMEWORK

  mkdir -p results/$MACHINE/$PKG
  for BENCH in HELLO PARAM DEEP AFTER_DEEP; do
    ./bench.sh $FRAMEWORK $BENCH $NTHREAD > results/$MACHINE/$NTHREAD/$PKG/$BENCH.log
  done
done