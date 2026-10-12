#!/bin/sh
# Terminal commands for the local Supabase, like the test server's.
# Run from anywhere: Supabase/send.sh m "hello"
#
# Events go to the newest user (the app's anonymous sign-in), or to
# USER_ID=<uuid> if set. `users` lists them.

set -eu

PROJECT=gym-socket-demo
DB=supabase_db_$PROJECT
GATEWAY=supabase_kong_$PROJECT
REALTIME=supabase_realtime_$PROJECT

usage() {
    cat <<'EOF'
Usage: Supabase/send.sh <command> [text]

  m [text]   Send a message (default: "Great session!")
  n [title]  Send a notification (default: "Class starts in 10 min")
  u          Send an event with an unknown type (workoutPoll)
  list       List stored events, newest last
  users      List users, newest first
  drop       Restart Realtime: drops every socket, the app reconnects
  offline    Stop the API gateway: socket and HTTP unreachable,
             the database keeps running so m/n/u still work
  online     Start the API gateway again
EOF
}

# Runs SQL from stdin. `-v name=value` arguments are passed to psql and
# quoted with :'name', so text with quotes in it is safe.
sql() {
    docker exec -i "$DB" psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 "$@"
}

target_user() {
    if [ -n "${USER_ID:-}" ]; then
        echo "$USER_ID"
        return
    fi
    user=$(echo "select id from auth.users order by created_at desc limit 1;" | sql -At)
    if [ -z "$user" ]; then
        echo "No users yet. Start the app in Supabase mode first, or set USER_ID." >&2
        exit 1
    fi
    echo "$user"
}

insert() {
    # $1 = type, $2 = payload SQL using :'text'
    # `exit` inside $(...) only leaves the subshell, so stop here too.
    user=$(target_user) || exit 1
    sql -v user="$user" -v text="$3" <<EOF
insert into public.events (user_id, type, payload)
values (:'user', '$1', $2)
returning sequence, type, id, payload;
EOF
}

command=${1:-}
text=${2:-}
poll_default="Rate today's class"

case "$command" in
m)
    insert message \
        "jsonb_build_object('chatID', '42', 'senderID', 'coach', 'text', :'text')" \
        "${text:-Great session!}"
    ;;
n)
    insert notification \
        "jsonb_build_object('title', :'text', 'body', 'Leg day, studio 2', 'workoutID', 'legs-1')" \
        "${text:-Class starts in 10 min}"
    ;;
u)
    insert workoutPoll \
        "jsonb_build_object('question', :'text')" \
        "${text:-$poll_default}"
    ;;
list)
    echo "select sequence, type, id, user_id, payload, created_at from public.events order by sequence;" | sql
    ;;
users)
    echo "select id, is_anonymous, created_at from auth.users order by created_at desc;" | sql
    ;;
drop)
    docker restart "$REALTIME" >/dev/null
    echo "Realtime restarted: all sockets dropped."
    ;;
offline)
    docker stop "$GATEWAY" >/dev/null
    echo "Offline: the app cannot reach Supabase. m/n/u still store events."
    ;;
online)
    docker start "$GATEWAY" >/dev/null
    echo "Online again."
    ;;
*)
    usage
    exit 1
    ;;
esac
