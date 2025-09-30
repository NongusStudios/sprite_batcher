#!/bin/sh
if [ ! -d bin ]; then
    mkdir bin
fi

odin build examples -debug -out:bin/examples.out -o:speed
if [ "$1" = "run" ]; then
    ./bin/examples.out
fi