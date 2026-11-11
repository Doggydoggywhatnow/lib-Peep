#!/bin/sh
# JDK 21 has the foreign-function API as a preview feature; JDK 22+ has it final.
set -e
V=$(javac -version 2>&1 | sed 's/[^0-9]*\([0-9]*\).*/\1/')
rm -rf out
if [ "$V" -ge 22 ]; then
  javac -d out Peep.java Demo.java 2>/dev/null
  java --enable-native-access=ALL-UNNAMED -cp out Demo
else
  javac --release 21 --enable-preview -d out Peep.java Demo.java 2>/dev/null
  java --enable-preview --enable-native-access=ALL-UNNAMED -cp out Demo
fi
