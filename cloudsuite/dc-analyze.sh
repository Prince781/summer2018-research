#!/bin/sh

grep -E "  1.[[:digit:]]+," | sed 's/,//g' | awk '{sum+=$1;sum_rps+=$2}END{printf "Total time: %.3f s\n", sum; printf "Average requests/s: %.3f\n", (sum_rps/NR)}'
