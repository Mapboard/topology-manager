source defs.sh
cat $1 | psql $dbname -v srid=$srid >&2

