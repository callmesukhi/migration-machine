#!/usr/bin/env bash
# Test fixture: records that it ran, then succeeds.
touch "$MARKER_DIR/ran_$STEP_ID"
echo "ran $STEP_ID"
exit 0
