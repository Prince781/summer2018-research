#!/bin/sh

grep -E "^  1.[[:digit:]]+," | sed 's/,//g' | awk 'BEGIN{print "time, rps, latency"}; {sum_time+=$1;sum_rps+=$2;sum_lat+=$8; printf "%.3f, %.3f, %.3f\n", sum_time, $2, $8}END{printf "Total time: %.3f s\n", sum_time; printf "Average requests/s: %.3f\n", (sum_rps/NR); printf "Average latency: %.3f\n", (sum_lat/NR)}'
