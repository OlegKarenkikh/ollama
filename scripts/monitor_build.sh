#!/bin/sh
#
# Мониторинг сборки с отчетом каждые 10 минут
#

set -eu

LOG_FILE=${1:-"/tmp/build_final.log"}
INTERVAL=${2:-600}  # 10 минут в секундах

echo "Monitoring build log: $LOG_FILE"
echo "Report interval: $INTERVAL seconds (10 minutes)"
echo ""

LAST_LINE=0
REPORT_COUNT=0

while true; do
    sleep $INTERVAL
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file not found, waiting..."
        continue
    fi
    
    CURRENT_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_LINES" -gt "$LAST_LINE" ]; then
        REPORT_COUNT=$((REPORT_COUNT + 1))
        echo ""
        echo "=========================================="
        echo "BUILD STATUS REPORT #$REPORT_COUNT"
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo "Total log lines: $CURRENT_LINES"
        echo "New lines since last report: $((CURRENT_LINES - LAST_LINE))"
        echo ""
        echo "--- Last 20 lines of build log ---"
        tail -20 "$LOG_FILE" | sed 's/^/  /'
        echo ""
        echo "--- Current build stage ---"
        tail -50 "$LOG_FILE" | grep -E "^#[0-9]+|DONE|ERROR|CANCELED" | tail -10 | sed 's/^/  /'
        echo "=========================================="
        
        LAST_LINE=$CURRENT_LINES
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new log entries..."
    fi
done
