#!/usr/bin/env bash

$DMD -m${MODEL} -of${OUTPUT_BASE}/printenv${EXE} ${EXTRA_FILES}/printenv.d
${OUTPUT_BASE}/printenv${EXE} > ${OUTPUT_BASE}/envFromExe.txt

$DMD -m${MODEL} -run ${EXTRA_FILES}/printenv.d > ${OUTPUT_BASE}/envFromRun.txt

diff -p ${OUTPUT_BASE}/envFromExe.txt ${OUTPUT_BASE}/envFromRun.txt

rm -f ${OUTPUT_BASE}/*
