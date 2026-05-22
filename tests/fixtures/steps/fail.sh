#!/usr/bin/env bash
# Test fixture: records that it ran, then fails on purpose.
touch "$MARKER_DIR/ran_$STEP_ID"
echo "ran $STEP_ID (intentional failure)"
exit 1
