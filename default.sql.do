source defs.sh
cat $1 | psql $dbname >&2

