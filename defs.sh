here="$(dirname "$(readlink -f "$0")")"

base=${here:h}
dbname="little_ambergris_post_hurricane"
host="131.215.67.27"
srid=32619

db_connection=PG:"dbname='$dbname' host='$host' user='Daven' password='Daven'"

function sql {
  psql $dbname -h $host $@
}
