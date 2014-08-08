#!/bin/bash

# config
TMPDIR=./tmp
# arguments

HELP="$0 PROG BENCH [BENCH_TIME=30s] [NBENCH=10] [PORT=8080]
    PROG: apiary, scotty, spock
    BENCH: HELLO, PARAM, DEEP, AFTER_DEEP"

if [ $# -eq 2 ]; then
  PROG=$1
  BENCH=$2
  NBENCH=10
  BENCHTIME="30s"
  PORT=8080
elif [ $# -eq 3 ]; then
  PROG=$1
  BENCH=$2
  NBENCH=$3
  BENCHTIME="30s"
  PORT=8080
elif [ $# -eq 4 ]; then
  PROG=$1
  BENCH=$2
  NBENCH=$3
  BENCHTIME=$4
  PORT=8080
elif [ $# -eq 5 ]; then
  PROG=$1
  BENCH=$2
  NBENCH=$3
  BENCHTIME=$4
  PORT=$5
else
  echo "$HELP"
  exit 1
fi

WRK="wrk -t8 -c400 -d$BENCHTIME"

HELLO_URL="http://localhost:$PORT/echo/hello-world"
PARAM_URL="http://localhost:$PORT/echo/plain/hello/12"
DEEP_URL="http://localhost:$PORT/deep/foo/bar/baz/100"
AFTER_DEEP_URL="http://localhost:$PORT/after"

if   [ "$BENCH" == "HELLO" ]; then
  URL=$HELLO_URL
elif [ "$BENCH" == "PARAM" ]; then
  URL=$PARAM_URL
elif [ "$BENCH" == "DEEP" ]; then
  URL=$DEEP_URL
elif [ "$BENCH" == "AFTER_DEEP" ]; then
  URL=$AFTER_DEEP_URL
fi

if ! which wrk > /dev/null; then
  echo "wrk not found." >&2
  exit 127
fi

# start server 
echo -n "server start. " >&2
if [ -e ./dist/build/$PROG/$PROG ]; then
  ./dist/build/$PROG/$PROG $PORT &
  sleep 30
  pid=$!
  echo "pid: $pid" >&2
else
  echo "$HELP"
  exit 2
fi

trap "echo server stop pid: $pid >&2 && kill $pid && echo remove $TMPDIR >&2 && rm -rf $TMPDIR" EXIT

echo make $TMPDIR directory >&2
mkdir $TMPDIR

# bench configuration

bench () {
  tmp=`mktemp $TMPDIR/bench.XXXXXXXXXXX`
  for i in `seq 1 $NBENCH`; do
    echo bench $i start >&2
    result=$($WRK $1)
    echo "$result" | awk '/^Requests\/sec:/{print $2}' >> $tmp
    echo "$result"
  done

  echo "=================== summary ==================="
  echo "bench target: $PROG"
  echo "bench mode:   $BENCHTIME * $NBENCH"
  ave=`awk -f average.awk $tmp`
  echo "average:      $ave"
  stdev=`awk -vave=$ave -f stdev.awk $tmp`
  echo "stdev:        $stdev"
}

echo "Benchmarking $BENCH"
bench $URL

#echo "Benchmarking $HELLO_URL (no regex, no captures)"
#bench $HELLO_URL
#
#echo "Benchmarking $PARAM_URL (simple captures, no regex)"
#bench $PARAM_URL
