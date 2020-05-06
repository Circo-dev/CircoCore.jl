#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only

# Simple test helper script that starts multiple nodes on the local machine

NODE_COUNT=2
ROOTS_FILE=roots.txt
SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
NODESTART_SCRIPT="$SOURCE_DIR/circonode.sh"

command="$NODESTART_SCRIPT --rootsfile $ROOTS_FILE"

# Start first node as root and setup zygote
rm -f $ROOTS_FILE
$command --add -z&

# Other nodes
while [ ! -f $ROOTS_FILE ]; do sleep 0.1; done
for i in `seq 2 $NODE_COUNT`; do
    $command&
done
wait
