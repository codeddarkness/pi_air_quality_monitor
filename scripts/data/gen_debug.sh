#!/usr/bin/env bash
## debug for check_ranges.func

mkdir -p tmp logs
dbgfunc=debug.func

grep = check_ranges.func | cut -d'=' -f1 | grep -v if | tr -d ' ' | sed 's/^\s*//g' > tmp/debug.vars
sed 's/^/\$\{/g' tmp/debug.vars | sed 's/$/:-NULL\}/g'  > tmp/debug.values
echo 'function range_debug(){' > $dbgfunc
echo 'mkdir -p logs' >> $dbgfunc
echo 'touch logs/check_ranges-debug.log' >> $dbgfunc
echo 'cat << EDBG >> logs/check_ranges-debug.log' >> $dbgfunc
paste tmp/debug.vars tmp/debug.values | column -t >> ${dbgfunc}
echo  >> $dbgfunc
echo 'EDBG' >> $dbgfunc
echo '}' >> $dbgfunc

