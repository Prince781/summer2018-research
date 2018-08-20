#!/bin/sh

grep -E "^  1.[[:digit:]]+," | sed 's/,//g' | awk 'BEGIN{print "time, rps\n"}; {sum+=$1;sum_rps+=$2; printf "%.3f, %.3f\n", sum, $2}END{printf "Total time: %.3f s\n", sum; printf "Average requests/s: %.3f\n", (sum_rps/NR)}'
