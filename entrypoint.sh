#!/bin/sh
# entrypoint.sh

# If variables are set in Koyeb, upsert the superuser account
if [ -n "$PB_ADMIN_EMAIL" ] && [ -n "$PB_ADMIN_PASSWORD" ]; then
    echo "Configuring superuser: $PB_ADMIN_EMAIL"
    ./backend_bin superuser upsert "$PB_ADMIN_EMAIL" "$PB_ADMIN_PASSWORD"
fi

# Start the server using the flags identified in the Makefile/Architecture
# --dir ensures PocketBase uses the volume-mounted path for data
exec ./backend_bin serve --http=0.0.0.0:8090 --dir=/app/pb_data
