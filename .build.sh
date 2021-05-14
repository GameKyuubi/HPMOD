#!/bin/bash

out=".build/KL_HPMOD_test.pk3"

if [ -f "$out" ] ; then
  rm "$out"
fi

./.srb2kz . ./$out
