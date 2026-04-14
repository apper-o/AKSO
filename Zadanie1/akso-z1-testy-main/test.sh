#!/bin/bash

id=$1
mem=$2

returnCode=0

oPassed=0
oAll=0

tPassed=0
tAll=0

if [ $id == "all" ]
then
    for i in {1..20}
    do
        bash test.sh $i $mem
        if [[ $? == 0 ]]
        then
            tPassed=$((tPassed+1))
        fi
        tAll=$((tAll+1))
    done
    echo;
    echo "Passed $tPassed / $tAll tests"
else
    if [[ $mem == "false" ]]
    then
        ./tester $id
        returnCode=$?
    else
        valgrind --leak-check=full --errors-for-leak-kinds=all --show-leak-kinds=all --quiet --error-exitcode=69 ./tester $id
        returnCode=$?
    fi

    for t in ./tests/output/test${id}_*.model.out
    do
        if diff -q "${t%model.out}result.out" $t
        then
            oPassed=$((oPassed + 1))
        else
            diff "${t%model.out}out" $t -y
        fi
        oAll=$((oAll + 1))
    done
    echo "Output files (rstack_write): $oPassed / $oAll correct"
    echo "-----------------------------------------------"
    if [[ $oPassed == $oAll && $returnCode == 0 ]]
    then
        echo "PASSED"
        exit 0
    else
        echo "FAILED"
        exit 67
    fi
fi

