#!/bin/bash
# Gracefully stop the application
if [ -f /opt/quiz_project/_build/prod/rel/quiz_project/bin/quiz_project ]; then
  /opt/quiz_project/_build/prod/rel/quiz_project/bin/quiz_project stop || true
fi
