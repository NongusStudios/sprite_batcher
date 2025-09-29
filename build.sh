#!/bin/sh
odin build examples -debug -out:bin/examples.out -o:speed
if [ "$1" = "run" ]; then
    ./bin/examples.out
fi