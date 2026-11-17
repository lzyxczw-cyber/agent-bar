#!/usr/bin/env bash
pkill -f '/agentbar/agentbar' 2>/dev/null || pkill -f 'agentbar' 2>/dev/null || true
echo "agentbar stopped (if it was running)"
