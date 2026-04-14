#!/bin/bash
set -e
rm -rf generations
mkdir generations
cp bin/builder generations/gen1
cd generations

CURRENT="./gen1"
for i in $(seq 2 50); do
    $CURRENT
    NEXT=$(ls -t | grep -v "gen" | head -1)
    mv "$NEXT" "gen$i"
    chmod +x "gen$i"
    CURRENT="./gen$i"
done
echo "Generations successfully generated."

total_diff=0
count=0
echo "Calculating byte differences between generations..."
for i in $(seq 2 50); do
    diff_bytes=$(cmp -l "gen$((i-1))" "gen$i" | wc -l || true)
    filesize=$(stat -c%s "gen$i")
    percent=$(awk "BEGIN {printf \"%.2f\", ($diff_bytes/$filesize)*100}")
    if [ $i -le 6 ]; then
        echo "Gen $((i-1)) -> Gen $i: $diff_bytes differing bytes out of $filesize ($percent%)"
    fi
    total_diff=$((total_diff + diff_bytes))
    count=$((count + 1))
done
avg=$((total_diff / count))
echo "Average difference across $count pairs: ~$avg bytes"
cd ..
