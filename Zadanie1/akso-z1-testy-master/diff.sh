#!/bin/bash

id=$1

passed=0
all=0

for t in ./tests/test${id}_*.model.out
do
    if diff -q "${t%model.out}result.out" $t
    then
        passed=$((passed + 1))
    else
        diff "${t%model.out}out" $t -y
    fi
    all=$((all + 1))
done

echo Files written: $passed / $all correct