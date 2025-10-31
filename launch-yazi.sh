#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title launch-yazi
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🤖
# @raycast.packageName Ui Tools

# Documentation:
# @raycast.description Launch yazi file browser
# @raycast.author drucial_white
# @raycast.authorURL https://raycast.com/drucial_white

/Applications/kitty.app/Contents/MacOS/kitty --single-instance --directory=~ yazi
