-- Create a dedicated replication user
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'replicator_password';

-- Create the application user
CREATE USER app WITH ENCRYPTED PASSWORD 'app_password';

-- Create the application database
CREATE DATABASE runtime_sentinel OWNER app;

-- Allow the replicator to connect (needed for monitoring queries)
GRANT CONNECT ON DATABASE runtime_sentinel TO replicator;