# Chapter 5: Process Architecture

## Introduction

PostgreSQL employs a multi-process architecture rather than a multi-threaded model, a fundamental design decision that has shaped its reliability, security, and portability characteristics. This chapter provides a comprehensive examination of PostgreSQL's process model, covering everything from the postmaster's supervisory role to the intricate details of backend process lifecycle management, inter-process communication mechanisms, and the client/server protocol.

The process architecture consists of three primary categories:
1. **Postmaster**: The main supervisor process that manages all other processes
2. **Backend processes**: Processes that handle client connections and queries
3. **Auxiliary processes**: Background workers that perform system maintenance tasks

This multi-process approach provides strong fault isolation—a crash in one backend does not directly corrupt other backends or the postmaster. Each process operates with its own memory space, and shared state is managed explicitly through shared memory and well-defined IPC mechanisms.

## 1. The Process Model Philosophy

### 1.1 Why Multi-Process vs Multi-Threading?

PostgreSQL's choice of a multi-process architecture over multi-threading was deliberate and remains justified by several factors:

**Fault Isolation**: When a backend process crashes due to a bug or assertion failure, only that process terminates. The operating system ensures complete cleanup of process resources. In a multi-threaded model, a single thread's corruption could potentially affect the entire server's address space.

**Portability**: In the early 1990s when PostgreSQL (then Postgres95) was being developed, thread implementations varied significantly across Unix platforms. POSIX threads were not yet standardized, and thread support on Windows was entirely different. A process-based model provided consistent behavior across all platforms.

**Security**: Process boundaries provide natural security isolation. Each backend process can have different effective privileges, and the kernel enforces memory protection between processes.

**Simplicity**: Programming with processes is often simpler than thread programming. There's no need for fine-grained locking around every shared data structure, and stack-allocated variables are naturally thread-local (process-local).

**Modern Considerations**: While thread overhead has decreased on modern systems, PostgreSQL's architecture has evolved to optimize the process model with connection pooling (external tools like PgBouncer), prepared connections, and efficient process spawning.

### 1.2 Process Hierarchy

```
postmaster (PID 1234)
├── logger (syslogger)
├── checkpointer
├── background writer
├── walwriter
├── autovacuum launcher
│   ├── autovacuum worker 1
│   ├── autovacuum worker 2
│   └── autovacuum worker 3
├── archiver (if enabled)
├── stats collector
├── logical replication launcher
│   ├── logical replication worker 1
│   └── logical replication worker 2
├── WAL sender 1 (streaming replication)
├── WAL sender 2 (streaming replication)
├── backend process (client 1)
├── backend process (client 2)
├── backend process (client 3)
└── parallel worker pool
    ├── parallel worker 1
    ├── parallel worker 2
    └── parallel worker 3
```

All processes are children of the postmaster, which serves as the supervisory process. The postmaster never directly touches shared memory—this isolation ensures that if shared memory becomes corrupted, the postmaster can detect the problem and initiate recovery.

## 2. The Postmaster: Supervisor and Guardian

### 2.1 Role and Responsibilities

The postmaster (`src/backend/postmaster/postmaster.c`) is the first PostgreSQL process started when the server begins. Its responsibilities include:

1. **Initialization**: Reading configuration files, validating settings, creating shared memory
2. **Process Spawning**: Launching auxiliary processes and client backend processes
3. **Connection Management**: Listening for client connections, authenticating clients
4. **Supervision**: Monitoring child processes, detecting crashes, coordinating recovery
5. **Shutdown Coordination**: Managing orderly shutdown or emergency recovery
6. **Signal Handling**: Responding to administrative signals (SIGHUP, SIGTERM, etc.)

### 2.2 Startup Sequence

When PostgreSQL starts, the postmaster performs the following sequence:

```c
/* Simplified postmaster startup sequence */

1. Parse command-line arguments
   - Data directory location (-D)
   - Configuration file overrides
   - Port number (-p)

2. Read postgresql.conf and postgresql.auto.conf
   - Load all configuration parameters
   - Validate settings

3. Verify data directory
   - Check for postmaster.pid (detect already-running instance)
   - Verify directory permissions
   - Check PostgreSQL version compatibility

4. Create and attach shared memory
   - Calculate shared memory size requirements
   - Create System V shared memory segments (or mmap on some platforms)
   - Initialize shared memory structures

5. Load pg_hba.conf and pg_ident.conf
   - Parse authentication rules
   - Build in-memory representation

6. Open listen sockets
   - Bind to configured addresses (listen_addresses)
   - Listen on configured port (default 5432)
   - Handle Unix domain sockets

7. Write postmaster.pid file
   - Record PID, data directory, port, socket directory
   - Used to detect running instance

8. Start auxiliary processes
   - logger (if logging_collector = on)
   - startup process (for crash recovery or archive recovery)
   - After recovery completes:
     * checkpointer
     * background writer
     * walwriter
     * autovacuum launcher
     * archiver (if archiving enabled)
     * stats collector
     * logical replication launcher

9. Enter main event loop
   - Accept client connections
   - Monitor child processes
   - Handle signals
```

### 2.3 The Postmaster Never Touches Shared Memory

A critical architectural principle: **after initialization, the postmaster never reads or writes shared memory**. This design choice has important implications:

**Rationale**:
- If shared memory becomes corrupted (due to a bug, hardware error, or malicious action), the postmaster remains unaffected
- The postmaster can detect that something is wrong (child processes crashing) and initiate recovery
- If the postmaster itself accessed corrupted shared memory, it could crash, leaving no supervisor to coordinate recovery

**Implementation**:
```c
/* From src/backend/postmaster/postmaster.c */

/*
 * The postmaster never accesses shared memory after initialization.
 * All communication with backends is done via:
 * - Process signals (SIGUSR1, SIGUSR2, SIGTERM, etc.)
 * - Exit status of child processes
 * - Pipes for data transfer (e.g., statistics)
 *
 * This isolation ensures the postmaster can always detect and
 * respond to backend crashes.
 */
```

**Communication Mechanisms**:
- **Signals**: The postmaster sends signals to children (SIGTERM for shutdown, SIGUSR1 for cache invalidation)
- **Exit Status**: The postmaster uses `waitpid()` to detect child termination and exit codes
- **Pipes**: Some auxiliary processes (like stats collector) send data to the postmaster via pipes

### 2.4 Process Spawning

When a client connects, the postmaster performs the following steps:

```
Client Connection Flow:
┌─────────┐                          ┌───────────┐
│ Client  │                          │Postmaster │
└────┬────┘                          └─────┬─────┘
     │                                     │
     │ 1. TCP connect to port 5432         │
     ├────────────────────────────────────>│
     │                                     │
     │                                     │ 2. accept() connection
     │                                     │    - Get client address
     │                                     │    - Check connection limits
     │                                     │    - Create socket
     │                                     │
     │                                     │ 3. fork() new backend
     │                                     ├──────────┐
     │                                     │          │
     │                                     │    ┌─────▼─────┐
     │                                     │    │  Backend  │
     │<─────────────────────────────────────────┤   Child   │
     │ 4. Backend inherits socket          │    └───────────┘
     │                                     │          │
     │                                     │          │ 5. Authenticate
     │                                     │          │    - Check pg_hba.conf
     │<─────────────────────────────────────────────────┤    - Verify credentials
     │ 6. Send auth request (e.g., MD5)    │          │
     ├───────────────────────────────────────────────>│
     │ 7. Send password hash               │          │
     │                                     │          │ 8. Verify password
     │<─────────────────────────────────────────────────┤
     │ 9. Auth OK, Ready for Query         │          │
     │                                     │          │
     │                                     │          │ 10. Enter main loop
     │ 11. Query messages                  │          │     - Process queries
     ├───────────────────────────────────────────────>│     - Execute commands
     │<─────────────────────────────────────────────────┤     - Return results
     │ 12. Results                         │          │
```

**Key Code Path** (`src/backend/postmaster/postmaster.c`):

```c
/*
 * BackendStartup -- connection setup and authentication
 */
static int
BackendStartup(Port *port)
{
    Backend *bn;

    /* Limit number of concurrent backends */
    if (CountChildren(BACKEND_TYPE_NORMAL) >= MaxBackends)
    {
        ereport(LOG,
                (errcode(ERRCODE_TOO_MANY_CONNECTIONS),
                 errmsg("sorry, too many clients already")));
        return STATUS_ERROR;
    }

    /* Fork the backend process */
    bn = (Backend *) malloc(sizeof(Backend));
    bn->pid = fork_process();

    if (bn->pid == 0)  /* Child process */
    {
        /* Close postmaster's sockets */
        ClosePostmasterPorts(false);

        /* Perform authentication */
        InitPostgres(port->database_name, port->user_name);

        /* Enter main backend loop */
        PostgresMain(port);

        /* Should not return */
        proc_exit(0);
    }

    /* Parent (postmaster) continues */
    return STATUS_OK;
}
```

### 2.5 Signal Handling

The postmaster responds to various Unix signals:

| Signal | Action | Purpose |
|--------|--------|---------|
| **SIGHUP** | Reload configuration | Re-reads `postgresql.conf`, `pg_hba.conf`, and `pg_ident.conf`; signals all children to reload |
| **SIGTERM** | Smart Shutdown | Wait for all clients to disconnect, then shutdown |
| **SIGINT** | Fast Shutdown | Terminate all backends, then shutdown |
| **SIGQUIT** | Immediate Shutdown | Emergency shutdown without cleanup (like a crash) |
| **SIGUSR1** | Internal signaling | Used for inter-process communication (varies by recipient) |
| **SIGUSR2** | Internal signaling | Reserved for future use in some processes |
| **SIGCHLD** | Child process exit | Reap zombie processes, detect crashes |

**Signal Handler** (`src/backend/postmaster/postmaster.c`):

```c
/*
 * sigusr1_handler -- handle SIGUSR1 from child processes
 */
static void
sigusr1_handler(SIGNAL_ARGS)
{
    int save_errno = errno;

    /* Don't process signals during critical sections */
    if (QueryCancelPending)
        QueryCancelHoldoffCount++;

    /* Set flag for main loop to check */
    got_SIGUSR1 = true;

    /* Wake up main loop if it's waiting */
    SetLatch(MyLatch);

    errno = save_errno;
}
```

## 3. Backend Processes

### 3.1 Backend Process Types

PostgreSQL has 18 different backend process types, each serving a specific role:

| Type | Constant | Purpose |
|------|----------|---------|
| **Normal Backend** | `B_BACKEND` | Handles regular client queries |
| **Autovacuum Worker** | `B_AUTOVAC_WORKER` | Performs automatic vacuum and analyze |
| **Autovacuum Launcher** | `B_AUTOVAC_LAUNCHER` | Coordinates autovacuum workers |
| **WAL Sender** | `B_WAL_SENDER` | Streams WAL to replicas |
| **WAL Receiver** | `B_WAL_RECEIVER` | Receives WAL on replica |
| **WAL Writer** | `B_WAL_WRITER` | Flushes WAL buffers to disk |
| **Background Writer** | `B_BG_WRITER` | Writes dirty buffers to disk |
| **Checkpointer** | `B_CHECKPOINTER` | Coordinates checkpoints |
| **Startup Process** | `B_STARTUP` | Performs recovery on startup |
| **Archiver** | `B_ARCHIVER` | Archives completed WAL files |
| **Stats Collector** | `B_STATS_COLLECTOR` | Collects and stores statistics |
| **Logger** | `B_LOGGER` | Captures server log output |
| **Logical Launcher** | `B_LOGICAL_LAUNCHER` | Manages logical replication workers |
| **Logical Worker** | `B_LOGICAL_WORKER` | Applies logical replication changes |
| **Parallel Worker** | `B_PARALLEL_WORKER` | Executes parallel query operations |
| **Standalone Backend** | `B_STANDALONE_BACKEND` | Single-user mode (no postmaster) |
| **Background Worker** | `B_BG_WORKER` | Custom background workers (extensions) |
| **Slotsync Worker** | `B_SLOTSYNC_WORKER` | Synchronizes replication slots |

### 3.2 Backend Process Lifecycle

A normal client backend goes through several phases during its lifetime:

```
Backend Lifecycle:
┌────────────────────────────────────────────────────────────┐
│ 1. FORK                                                    │
│    - Postmaster calls fork()                               │
│    - Child process inherits file descriptors               │
│    - Child closes postmaster-only descriptors              │
└──────────────┬─────────────────────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────────┐
│ 2. INITIALIZATION                                          │
│    - Set process title                                     │
│    - Initialize random number generator                    │
│    - Setup signal handlers                                 │
│    - Attach to shared memory                               │
│    - Create process latch                                  │
└──────────────┬─────────────────────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────────┐
│ 3. AUTHENTICATION                                          │
│    - Read startup packet from client                       │
│    - Check pg_hba.conf rules                               │
│    - Perform authentication (password, GSSAPI, etc.)       │
│    - Verify database and role exist                        │
└──────────────┬─────────────────────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────────┐
│ 4. INITIALIZATION COMPLETE                                 │
│    - Load database-specific catalog info                   │
│    - Initialize transaction state                          │
│    - Setup memory contexts                                 │
│    - Send ReadyForQuery message to client                  │
└──────────────┬─────────────────────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────────┐
│ 5. MAIN LOOP (PostgresMain)                                │
│    ┌────────────────────────────────────────┐              │
│    │ Loop:                                  │              │
│    │  - Wait for client message             │              │
│    │  - Read message type                   │              │
│    │  - Dispatch to handler                 │              │
│    │    * 'Q': Simple query                 │              │
│    │    * 'P': Parse                        │              │
│    │    * 'B': Bind                         │              │
│    │    * 'E': Execute                      │              │
│    │    * 'D': Describe                     │              │
│    │    * 'C': Close                        │              │
│    │    * 'S': Sync                         │              │
│    │    * 'X': Terminate                    │              │
│    │  - Execute query                       │              │
│    │  - Send results                        │              │
│    │  - Send ReadyForQuery                  │              │
│    └────────────────────────────────────────┘              │
└──────────────┬─────────────────────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────────┐
│ 6. SHUTDOWN                                                │
│    - Client sends Terminate message                        │
│    - OR postmaster signals shutdown                        │
│    - Close database connection                             │
│    - Release locks                                         │
│    - Flush pending output                                  │
│    - Detach from shared memory                             │
└──────────────┬─────────────────────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────────┐
│ 7. EXIT                                                    │
│    - proc_exit() cleanup                                   │
│    - Process terminates                                    │
│    - Postmaster reaps zombie process                       │
└────────────────────────────────────────────────────────────┘
```

### 3.3 Backend State Machine

Each backend maintains state information that determines what operations it can perform. The state machine has 13 distinct states:

```
Backend State Machine (src/include/tcop/tcopprot.h):

STATE_UNDEFINED
    │
    │ Backend starts
    │
    ▼
STATE_IDLE ◄────────────────────────────┐
    │                                   │
    │ Receive query                     │ Query complete
    │                                   │
    ▼                                   │
STATE_RUNNING ──────────────────────────┤
    │                                   │
    │ Begin transaction                 │
    │                                   │
    ▼                                   │
STATE_IDLE_IN_TRANSACTION ──────────────┤
    │                                   │
    │ Execute in transaction            │
    │                                   │
    ▼                                   │
STATE_RUNNING_IN_TRANSACTION ───────────┤
    │                                   │
    │ Error occurs                      │
    │                                   │
    ▼                                   │
STATE_IDLE_IN_TRANSACTION_ABORTED ──────┤
    │                                   │
    │ ROLLBACK                          │
    │                                   │
    └───────────────────────────────────┘

Additional specialized states:

STATE_FASTPATH
    - Using fastpath protocol for function calls

STATE_DISABLED
    - Backend is terminating, no new commands accepted

STATE_REPORTING
    - Sending error or notice messages

STATE_COPY_IN
    - Receiving COPY data from client

STATE_COPY_OUT
    - Sending COPY data to client

STATE_COPY_BOTH
    - Bidirectional COPY (for replication)

STATE_PREPARE
    - Preparing a transaction for two-phase commit

STATE_PORTAL_RUNNING
    - Executing a portal (cursor)
```

**State Transitions** (`src/backend/tcop/postgres.c`):

```c
/* Backend state indicators */
typedef enum
{
    STATE_UNDEFINED,              /* Bootstrap/initialization */
    STATE_IDLE,                   /* Waiting for command */
    STATE_RUNNING,                /* Executing query */
    STATE_IDLE_IN_TRANSACTION,    /* In transaction, awaiting command */
    STATE_RUNNING_IN_TRANSACTION, /* Executing query in transaction */
    STATE_IDLE_IN_TRANSACTION_ABORTED, /* Transaction failed, awaiting ROLLBACK */
    STATE_FASTPATH,               /* Executing fastpath function */
    STATE_DISABLED                /* Backend shutting down */
} BackendState;

/* Change backend state and update ps display */
static void
set_ps_display(const char *activity)
{
    /* Update process title visible in ps/top */
    if (update_process_title)
    {
        char *display_string;

        display_string = psprintf("%s %s %s %s",
                                  MyProcPort->user_name,
                                  MyProcPort->database_name,
                                  get_backend_state_string(),
                                  activity);

        set_ps_display_string(display_string);
    }
}
```

### 3.4 Main Backend Loop

The heart of a backend process is the `PostgresMain` function:

```c
/* Simplified PostgresMain from src/backend/tcop/postgres.c */

void
PostgresMain(const char *dbname, const char *username)
{
    sigjmp_buf  local_sigjmp_buf;

    /* Setup signal handlers */
    pqsignal(SIGHUP, PostgresSigHupHandler);
    pqsignal(SIGINT, StatementCancelHandler);
    pqsignal(SIGTERM, die);
    pqsignal(SIGUSR1, procsignal_sigusr1_handler);

    /* Initialize backend */
    InitPostgres(dbname, InvalidOid, username, InvalidOid, NULL, false);

    /* Setup error recovery point */
    if (sigsetjmp(local_sigjmp_buf, 1) != 0)
    {
        /* Error recovery: clean up and return to main loop */
        error_context_stack = NULL;
        EmitErrorReport();
        FlushErrorState();
        AbortCurrentTransaction();
        MemoryContextSwitchTo(TopMemoryContext);
    }

    /* Send ready for query */
    ReadyForQuery(DestRemote);

    /* Main message loop */
    for (;;)
    {
        int firstchar;

        /* Release storage left over from prior query cycle */
        MemoryContextResetAndDeleteChildren(MessageContext);

        /* Report idle status to stats collector */
        pgstat_report_activity(STATE_IDLE, NULL);

        /* Wait for client message */
        firstchar = ReadCommand();

        switch (firstchar)
        {
            case 'Q':  /* Simple query */
                {
                    const char *query_string;

                    query_string = pq_getmsgstring();
                    pq_getmsgend();

                    exec_simple_query(query_string);
                }
                break;

            case 'P':  /* Parse */
                exec_parse_message();
                break;

            case 'B':  /* Bind */
                exec_bind_message();
                break;

            case 'E':  /* Execute */
                exec_execute_message();
                break;

            case 'D':  /* Describe */
                exec_describe_message();
                break;

            case 'C':  /* Close */
                exec_close_message();
                break;

            case 'S':  /* Sync */
                finish_xact_command();
                ReadyForQuery(DestRemote);
                break;

            case 'X':  /* Terminate */
                proc_exit(0);
                break;

            default:
                ereport(FATAL,
                        (errcode(ERRCODE_PROTOCOL_VIOLATION),
                         errmsg("invalid frontend message type %d",
                                firstchar)));
        }
    } /* end of message loop */
}
```

## 4. Auxiliary Processes

Auxiliary processes are system background workers that perform essential maintenance and housekeeping tasks. Unlike client backends, they do not serve client connections.

### 4.1 Background Writer (bgwriter)

**Purpose**: Gradually writes dirty buffers to disk to reduce checkpoint I/O spikes.

**Location**: `src/backend/postmaster/bgwriter.c`

**Algorithm**:
```
Loop forever:
    1. Sleep for bgwriter_delay milliseconds (default 200ms)
    2. Scan shared buffer pool
    3. Identify dirty buffers that are:
       - Not recently modified
       - Not pinned by any backend
    4. Write up to bgwriter_lru_maxpages buffers (default 100)
    5. If too many buffers written, sleep longer (adaptive)
    6. Update statistics
```

**Configuration Parameters**:
- `bgwriter_delay`: Time between rounds (default 200ms)
- `bgwriter_lru_maxpages`: Maximum buffers to write per round (default 100)
- `bgwriter_lru_multiplier`: Multiplier for average recent usage (default 2.0)

**Key Code**:
```c
/* Main loop of background writer process */
void
BackgroundWriterMain(void)
{
    sigjmp_buf local_sigjmp_buf;

    /* Identify as bgwriter process */
    MyBackendType = B_BG_WRITER;

    for (;;)
    {
        long    cur_timeout;
        int     rc;

        /* Clear any already-pending wakeups */
        ResetLatch(MyLatch);

        /* Perform buffer writing */
        BgBufferSync();

        /* Sleep for bgwriter_delay, or until signaled */
        cur_timeout = BgWriterDelay;
        rc = WaitLatch(MyLatch,
                      WL_LATCH_SET | WL_TIMEOUT | WL_POSTMASTER_DEATH,
                      cur_timeout,
                      WAIT_EVENT_BGWRITER_MAIN);

        /* Emergency bailout if postmaster died */
        if (rc & WL_POSTMASTER_DEATH)
            proc_exit(1);
    }
}
```

### 4.2 Checkpointer

**Purpose**: Performs checkpoints—flushes all dirty buffers to disk and writes a checkpoint record to WAL.

**Location**: `src/backend/postmaster/checkpointer.c`

**Checkpoint Process**:
```
Checkpoint Algorithm:
1. Wait for checkpoint trigger:
   - checkpoint_timeout expired (default 5 minutes)
   - WAL segments reached max_wal_size
   - Manual CHECKPOINT command
   - Database shutdown

2. Begin checkpoint:
   - Update checkpoint state in shared memory
   - Write checkpoint start record to WAL

3. Flush all dirty buffers:
   - Scan entire buffer pool
   - Write all dirty buffers to disk
   - Spread writes over checkpoint_completion_target period
   - Throttle I/O to avoid overwhelming disk

4. Flush WAL:
   - Ensure all WAL up to checkpoint is on disk

5. Update control file:
   - Write checkpoint location to pg_control
   - fsync control file

6. Cleanup:
   - Remove old WAL files (if not needed for archiving/replication)
   - Update statistics
```

**Configuration Parameters**:
- `checkpoint_timeout`: Maximum time between automatic checkpoints (default 5min)
- `max_wal_size`: Checkpoint triggered when WAL exceeds this (default 1GB)
- `min_wal_size`: Keep at least this much WAL (default 80MB)
- `checkpoint_completion_target`: Fraction of interval to spread checkpoint (default 0.9)
- `checkpoint_warning`: Warn if checkpoints happen closer than this (default 30s)

**Key Code**:
```c
/* Perform a checkpoint */
void
CreateCheckPoint(int flags)
{
    CheckPoint  checkPoint;
    XLogRecPtr  recptr;

    /* Initialize checkpoint record */
    MemSet(&checkPoint, 0, sizeof(checkPoint));
    checkPoint.time = (pg_time_t) time(NULL);

    /* Write checkpoint start WAL record */
    recptr = XLogInsert(RM_XLOG_ID, XLOG_CHECKPOINT_ONLINE);

    /* Flush all dirty buffers to disk */
    CheckPointBuffers(flags);

    /* Flush WAL to disk */
    XLogFlush(recptr);

    /* Update control file with checkpoint location */
    UpdateControlFile();

    /* Cleanup old WAL files */
    RemoveOldXlogFiles();
}
```

### 4.3 WAL Writer

**Purpose**: Flushes WAL buffers to disk periodically, independent of transaction commits.

**Location**: `src/backend/postmaster/walwriter.c`

**Rationale**:
- Reduces latency for commits (WAL may already be flushed)
- Ensures WAL is persistent even if backend crashes before commit
- Provides more predictable I/O patterns

**Algorithm**:
```
Loop forever:
    1. Sleep for wal_writer_delay milliseconds (default 200ms)
    2. Check if there are unflushed WAL records
    3. If yes:
       - Call XLogBackgroundFlush()
       - Write unflushed WAL to disk
       - fsync WAL files
    4. Update statistics
```

**Configuration**:
- `wal_writer_delay`: Time between WAL flushes (default 200ms)
- `wal_writer_flush_after`: Amount of WAL to write before flushing (default 1MB)

### 4.4 Autovacuum Launcher and Workers

**Purpose**: Automatically vacuum and analyze tables to reclaim space and update statistics.

**Location**: `src/backend/postmaster/autovacuum.c`

**Architecture**:
```
Autovacuum Launcher (single process)
    │
    │ Monitors tables via statistics
    │ Decides which tables need vacuuming
    │
    ├─── Spawns Worker 1 ──> Vacuums table "users"
    ├─── Spawns Worker 2 ──> Vacuums table "orders"
    └─── Spawns Worker 3 ──> Analyzes table "products"

    Maximum workers: autovacuum_max_workers (default 3)
```

**Launcher Algorithm**:
```
Loop forever:
    1. Sleep for autovacuum_naptime (default 1 minute)
    2. Query statistics for each database:
       - Dead tuples count
       - Insert count (for analyze)
       - Last vacuum/analyze time
    3. For each database needing work:
       - Calculate priority (oldest, most dead tuples)
       - If worker slots available:
         * Fork autovacuum worker
         * Assign database and table
    4. Monitor worker processes
    5. Respect autovacuum_max_workers limit
```

**Worker Process**:
```c
/* Autovacuum worker main loop */
void
AutoVacWorkerMain(int argc, char *argv[])
{
    /* Connect to assigned database */
    InitPostgres(dbname, InvalidOid, NULL, InvalidOid, NULL, false);

    /* Get list of tables to vacuum */
    table_oids = get_tables_to_vacuum();

    /* Process each table */
    foreach(lc, table_oids)
    {
        Oid relid = lfirst_oid(lc);

        /* Perform vacuum or analyze */
        vacuum_rel(relid, params);

        /* Check if we should exit (shutdown signal) */
        if (got_SIGTERM)
            break;
    }

    /* Exit worker */
    proc_exit(0);
}
```

**Configuration**:
- `autovacuum`: Enable/disable autovacuum (default on)
- `autovacuum_max_workers`: Maximum worker processes (default 3)
- `autovacuum_naptime`: Time between launcher runs (default 1min)
- `autovacuum_vacuum_threshold`: Minimum updates before vacuum (default 50)
- `autovacuum_analyze_threshold`: Minimum updates before analyze (default 50)
- `autovacuum_vacuum_scale_factor`: Fraction of table size to add to threshold (default 0.2)

### 4.5 WAL Sender

**Purpose**: Streams write-ahead log to standby servers for replication.

**Location**: `src/backend/replication/walsender.c`

**Role**: Each WAL sender process serves one standby server, streaming WAL records as they are generated.

**Protocol**:
```
WAL Sender <--> WAL Receiver (on standby)

1. Standby connects with replication protocol
2. Standby sends start position (LSN)
3. WAL sender begins streaming from that position:

   Loop:
       - Wait for new WAL to be written
       - Read WAL records from WAL files
       - Send XLogData messages to standby
       - Receive standby feedback:
         * Write position (data written to disk)
         * Flush position (data fsynced)
         * Apply position (data replayed)
       - Update replication slot position
       - Sleep or wait for more WAL
```

**Key Code**:
```c
/* Main loop of WAL sender */
void
WalSndLoop(WalSndSendDataCallback send_data)
{
    for (;;)
    {
        /* Send any pending WAL */
        send_data();

        /* Wait for more WAL or standby feedback */
        WalSndWait(WAITSOCKET_READABLE | WAITSOCKET_WRITEABLE);

        /* Process any messages from standby */
        ProcessRepliesIfAny();

        /* Check for shutdown signal */
        if (got_SIGTERM)
            break;
    }
}
```

### 4.6 WAL Receiver (on standby)

**Purpose**: Receives WAL from primary server and writes it to local WAL files.

**Location**: `src/backend/replication/walreceiver.c`

**Process**:
```
1. Connect to primary server
2. Request WAL streaming from current replay position
3. Receive XLogData messages
4. Write WAL records to local WAL files
5. Notify startup process (which replays WAL)
6. Send feedback to primary (write/flush/apply positions)
```

### 4.7 Archiver

**Purpose**: Copies completed WAL files to archive location for point-in-time recovery.

**Location**: `src/backend/postmaster/pgarch.c`

**Algorithm**:
```
Loop forever:
    1. Sleep for archive_timeout or until signaled
    2. Check for completed WAL files:
       - Files marked as ready in archive_status/
    3. For each ready file:
       - Execute archive_command
       - If successful:
         * Mark file as .done
         * Delete .ready status file
       - If failed:
         * Retry with exponential backoff
         * Log warning after multiple failures
    4. Update statistics
```

**Configuration**:
- `archive_mode`: Enable archiving (default off)
- `archive_command`: Shell command to execute for each WAL file
- `archive_timeout`: Force segment switch after this time (default 0 = disabled)

**Example archive_command**:
```bash
# Copy to local directory
archive_command = 'cp %p /archive/%f'

# Copy to remote server via rsync
archive_command = 'rsync -a %p backup-server:/archive/%f'

# Use wal-g (backup tool)
archive_command = 'wal-g wal-push %p'
```

### 4.8 Statistics Collector

**Purpose**: Collects and aggregates database activity statistics.

**Location**: `src/backend/postmaster/pgstat.c`

**Architecture**:
```
Backends/Workers          Stats Collector
       │                         │
       │ Send stats via UDP      │
       ├────────────────────────>│
       │ (or shared memory)      │
       │                         │
       │                    Aggregates:
       │                    - Table stats
       │                    - Index stats
       │                    - Function stats
       │                    - Database stats
       │                         │
       │                    Periodically writes
       │                    to stats files
       │                         │
       │ Query pg_stat_* views   │
       │<────────────────────────┤
       │ Read from shared memory │
```

**Statistics Types**:
- **Database-level**: Connections, transactions, blocks read/hit
- **Table-level**: Scans, tuples inserted/updated/deleted, dead tuples
- **Index-level**: Scans, tuples read/fetched
- **Function-level**: Calls, total time, self time
- **Replication**: WAL sender status, replication lag

**Configuration**:
- `track_activities`: Track currently executing commands (default on)
- `track_counts`: Collect table/index access statistics (default on)
- `track_functions`: Track function call statistics (default none)
- `track_io_timing`: Collect I/O timing statistics (default off)

### 4.9 Logical Replication Launcher and Workers

**Purpose**: Manage logical replication subscriptions and apply changes.

**Location**: `src/backend/replication/logical/launcher.c`

**Architecture**:
```
Logical Replication Launcher
    │
    │ Monitors pg_subscription catalog
    │ Starts workers for active subscriptions
    │
    ├─── Worker 1 ──> Subscription "sub1"
    │                 - Connects to publisher
    │                 - Receives logical changes
    │                 - Applies to local tables
    │
    └─── Worker 2 ──> Subscription "sub2"
                      - Same as above
```

**Worker Process**:
1. Connect to publisher database
2. Create replication slot on publisher
3. Start logical decoding from slot position
4. Receive logical change records
5. Apply changes to local tables (INSERT/UPDATE/DELETE)
6. Handle conflicts (based on conflict resolution settings)
7. Track apply progress

### 4.10 Logger (syslogger)

**Purpose**: Collects log messages from all processes and writes to log files.

**Location**: `src/backend/postmaster/syslogger.c`

**Why Separate Process?**:
- Centralizes logging (one process writes to log files)
- Enables log rotation without interrupting backends
- Allows CSV format logs
- Supports stderr capture

**Architecture**:
```
All Processes                Logger Process
     │                            │
     │ Write to stderr            │
     │ (pipe redirect)            │
     ├───────────────────────────>│
     │                            │
     │                       Receives messages
     │                       Formats as needed
     │                       Writes to log file
     │                       Rotates when needed
     │                            │
     │                       Log Files:
     │                       - postgresql-2025-11-19.log
     │                       - postgresql-2025-11-19.csv
```

**Configuration**:
- `logging_collector`: Enable logger process (default off)
- `log_directory`: Directory for log files (default log/)
- `log_filename`: Filename pattern (default postgresql-%Y-%m-%d_%H%M%S.log)
- `log_rotation_age`: Age to force log rotation (default 1d)
- `log_rotation_size`: Size to force log rotation (default 10MB)
- `log_destination`: Output format (stderr, csvlog, syslog)

## 5. Shared Memory Architecture

### 5.1 Shared Memory Overview

Shared memory is the primary mechanism for sharing state between PostgreSQL processes. All backends and auxiliary processes attach to the same shared memory segments, enabling:

- **Shared buffer pool**: Cached disk pages
- **Lock tables**: Transaction locks, tuple locks, relation locks
- **Process array**: Information about all active processes
- **WAL buffers**: Write-ahead log before writing to disk
- **SLRU buffers**: Simple LRU caches (CLOG, subtrans, multixact)

**Creation**: Postmaster creates shared memory during startup. Size is calculated based on configuration parameters.

### 5.2 Shared Memory Layout

```
Shared Memory Layout (conceptual):

┌─────────────────────────────────────────────────────────┐
│ Shared Memory Header                                    │
│ - Magic number (version check)                          │
│ - Total size                                            │
│ - Segment offsets                                       │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Shared Buffer Pool (shared_buffers)                    │
│                                                         │
│ Array of BufferDesc (metadata):                        │
│ - Buffer tag (identifies which page)                   │
│ - State (IO in progress, dirty, valid, etc.)           │
│ - Usage count (for eviction policy)                    │
│ - Reference count (number of pins)                     │
│ - Lock (content lock, IO lock)                         │
│                                                         │
│ Buffer data pages (8KB each):                          │
│ [Page 0][Page 1][Page 2]...[Page N]                    │
│                                                         │
│ Default size: shared_buffers = 128MB                   │
│ Typical production: 25% of system RAM                  │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ WAL Buffers (wal_buffers)                              │
│                                                         │
│ Circular buffer for WAL records before disk write      │
│ - WAL insert locks (parallel WAL insertion)            │
│ - WAL insertion position                               │
│ - WAL flush position                                   │
│                                                         │
│ Default: min(16MB, 1/32 of shared_buffers)             │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Lock Tables                                            │
│                                                         │
│ Lock hash table (max_locks_per_transaction):           │
│ - Regular locks (table, row, tuple)                    │
│ - Predicate locks (for serializable isolation)         │
│                                                         │
│ Lock methods:                                          │
│ - AccessShareLock, RowShareLock, RowExclusiveLock,     │
│   ShareUpdateExclusiveLock, ShareLock,                 │
│   ShareRowExclusiveLock, ExclusiveLock,                │
│   AccessExclusiveLock                                  │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Process Array (PGPROC array)                           │
│                                                         │
│ One entry per process slot:                            │
│ - Process ID                                           │
│ - Database OID                                         │
│ - Transaction ID                                       │
│ - Wait event information                               │
│ - Locks held                                           │
│ - Latch for signaling                                  │
│ - Semaphore for waiting                                │
│                                                         │
│ Size: max_connections + autovacuum_max_workers + ...   │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ SLRU Buffers (Simple LRU caches)                       │
│                                                         │
│ - Transaction status (pg_xact)                         │
│ - Subtransactions (pg_subtrans)                        │
│ - MultiXact members (pg_multixact)                     │
│ - MultiXact offsets (pg_multixact)                     │
│ - Commit timestamps (pg_commit_ts)                     │
│ - Async notifications (pg_notify)                      │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Other Shared Structures                                │
│                                                         │
│ - Checkpointer state                                   │
│ - Background writer state                              │
│ - Autovacuum shared state                              │
│ - Replication slots                                    │
│ - Two-phase commit state                               │
│ - Prepared transactions                                │
│ - Parallel query DSM segments                          │
│ - Statistics (shared stats snapshots)                  │
└─────────────────────────────────────────────────────────┘
```

### 5.3 Shared Memory Initialization

**Key Code** (`src/backend/storage/ipc/ipci.c`):

```c
/*
 * CreateSharedMemoryAndSemaphores
 * Creates and initializes shared memory and semaphores.
 */
void
CreateSharedMemoryAndSemaphores(void)
{
    PGShmemHeader *shim = NULL;
    Size        size;

    /* Calculate total shared memory size */
    size = CalculateShmemSize();

    elog(DEBUG3, "invoking IpcMemoryCreate(size=%zu)", size);

    /* Create the shared memory segment */
    shim = PGSharedMemoryCreate(size, &sharedMemoryHook);

    /* Initialize shared memory header */
    InitShmemAllocation(shim);

    /*
     * Initialize subsystem shared memory structures
     */
    CreateSharedProcArray();      /* Process array */
    CreateSharedBackendStatus();  /* Backend status array */
    CreateSharedInvalidationState(); /* Cache invalidation */
    InitBufferPool();             /* Shared buffer pool */
    InitWALBuffers();             /* WAL buffers */
    InitLockTable();              /* Lock tables */
    InitPredicateLocks();         /* Predicate locks for SSI */
    InitSLRUBuffers();            /* SLRU caches */
    InitReplicationSlots();       /* Replication slots */
    InitTwoPhaseState();          /* Prepared transactions */
}
```

### 5.4 Buffer Management

The shared buffer pool is PostgreSQL's most important shared memory structure:

```c
/* Buffer descriptor (src/include/storage/buf_internals.h) */
typedef struct BufferDesc
{
    BufferTag   tag;              /* ID of page cached in this buffer */
    int         buf_id;           /* Buffer's index number (from 0) */

    /* State flags and reference count */
    pg_atomic_uint32 state;       /* Atomic state word */

    int         wait_backend_pid; /* Backend waiting for IO */

    slock_t     buf_hdr_lock;     /* Spinlock for buffer header */

    int         freeNext;         /* Link in freelist chain */

} BufferDesc;

/* Buffer tag uniquely identifies a page */
typedef struct BufferTag
{
    RelFileNode rnode;            /* Relation file node */
    ForkNumber  forkNum;          /* Fork number (main, FSM, VM, etc.) */
    BlockNumber blockNum;         /* Block number within relation */
} BufferTag;
```

**Buffer States** (encoded in atomic state word):
- **BM_DIRTY**: Page modified, needs write to disk
- **BM_VALID**: Page contains valid data
- **BM_TAG_VALID**: Buffer tag is valid
- **BM_IO_IN_PROGRESS**: I/O currently in progress
- **BM_IO_ERROR**: I/O error occurred
- **BM_JUST_DIRTIED**: Recently dirtied
- **BM_PERMANENT**: Permanent relation (not temp)
- **BM_CHECKPOINT_NEEDED**: Needs checkpoint

**Pin Count**: Number of backends currently using the buffer (prevents eviction)

**Usage Count**: For clock-sweep eviction algorithm (0-5)

## 6. Inter-Process Communication Mechanisms

### 6.1 Signals

PostgreSQL uses Unix signals extensively for process communication:

**Signal Types**:

| Signal | Sender → Receiver | Purpose |
|--------|-------------------|---------|
| **SIGUSR1** | Various → Backend | Multi-purpose signal; action depends on flags in shared memory |
| **SIGUSR1** | Backend → Postmaster | Backend ready to accept connections |
| **SIGTERM** | Postmaster → All | Shutdown request (fast shutdown) |
| **SIGQUIT** | Postmaster → All | Immediate shutdown (crash) |
| **SIGHUP** | Admin → Postmaster | Reload configuration files |
| **SIGINT** | User → Backend | Cancel current query |

**SIGUSR1 Uses** (determined by flags in PGPROC structure):
- Cache invalidation messages available
- Notify/listen messages available
- Parallel query worker should exit
- Catchup interrupt (for replication)
- Recovery conflict
- Notify for checkpoint start

**Signal Handler Example**:

```c
/* Backend SIGUSR1 handler (src/backend/tcop/postgres.c) */
static void
procsignal_sigusr1_handler(SIGNAL_ARGS)
{
    int save_errno = errno;

    /* Don't do anything in critical section */
    if (InterruptHoldoffCount > 0)
    {
        InterruptPending = true;
        errno = save_errno;
        return;
    }

    /* Check various flags to determine what to do */
    if (CheckProcSignal(PROCSIG_CATCHUP_INTERRUPT))
    {
        /* Handle catchup interrupt for replication */
        HandleCatchupInterrupt();
    }

    if (CheckProcSignal(PROCSIG_NOTIFY_INTERRUPT))
    {
        /* Process NOTIFY messages */
        HandleNotifyInterrupt();
    }

    if (CheckProcSignal(PROCSIG_BARRIER))
    {
        /* Process barrier event */
        ProcessBarrierPlaceholder();
    }

    /* ... more checks ... */

    SetLatch(MyLatch);
    errno = save_errno;
}
```

### 6.2 Latches

Latches are a lightweight signaling mechanism that allows a process to sleep until woken by another process or a timeout.

**Use Cases**:
- Backend waiting for I/O completion
- WAL sender waiting for new WAL or standby feedback
- Background writer waiting for next cycle
- Backend waiting for lock

**API**:
```c
/* Initialize a latch */
void InitLatch(Latch *latch);

/* Set (wake) a latch */
void SetLatch(Latch *latch);

/* Wait on a latch */
int WaitLatch(Latch *latch, int wakeEvents, long timeout,
              uint32 wait_event_info);

/* Reset latch to non-set state */
void ResetLatch(Latch *latch);
```

**Wait Events**:
- `WL_LATCH_SET`: Wake when latch is set
- `WL_SOCKET_READABLE`: Wake when socket is readable
- `WL_SOCKET_WRITEABLE`: Wake when socket is writable
- `WL_TIMEOUT`: Wake after timeout expires
- `WL_POSTMASTER_DEATH`: Wake if postmaster dies

**Example Usage**:
```c
/* Wait for work or timeout */
int rc;

rc = WaitLatch(MyLatch,
               WL_LATCH_SET | WL_TIMEOUT | WL_POSTMASTER_DEATH,
               BgWriterDelay,
               WAIT_EVENT_BGWRITER_MAIN);

if (rc & WL_POSTMASTER_DEATH)
{
    /* Postmaster died, emergency exit */
    proc_exit(1);
}

if (rc & WL_LATCH_SET)
{
    /* Latch was set, we have work to do */
    ResetLatch(MyLatch);
    /* ... do work ... */
}

if (rc & WL_TIMEOUT)
{
    /* Timeout expired, time for regular work cycle */
    /* ... do work ... */
}
```

### 6.3 Spinlocks

Spinlocks are the lowest-level synchronization primitive, used to protect very short critical sections in shared memory.

**Characteristics**:
- Very fast when uncontended
- Should be held for only a few instructions
- Not safe to hold across any operation that could sleep or error
- Implemented using atomic CPU instructions (e.g., test-and-set)

**Usage**:
```c
/* Acquire spinlock */
SpinLockAcquire(&bufHdr->buf_hdr_lock);

/* Critical section - must be very short */
bufHdr->refcount++;

/* Release spinlock */
SpinLockRelease(&bufHdr->buf_hdr_lock);
```

**Guidelines**:
- Never hold spinlock across I/O operation
- Never hold spinlock across memory allocation
- Never hold spinlock when calling elog/ereport
- Never acquire heavyweight lock while holding spinlock
- Keep critical section under ~100 instructions

### 6.4 Lightweight Locks (LWLocks)

LWLocks are used for short-to-medium duration locks on shared memory structures.

**Characteristics**:
- Support shared (read) and exclusive (write) modes
- Processes sleep if lock is contended (unlike spinlocks)
- Safe to hold across operations that might error
- More overhead than spinlocks, less than heavyweight locks

**Common LWLocks**:
- **BufMappingLock**: Protects buffer mapping table
- **LockMgrLock**: Protects lock manager hash tables
- **WALInsertLock**: Protects WAL insertion (multiple locks for parallelism)
- **WALWriteLock**: Serializes WAL writes to disk
- **CheckpointerCommLock**: Coordinates checkpoint process
- **XidGenLock**: Protects transaction ID generation

**API**:
```c
/* Acquire LWLock in exclusive mode */
LWLockAcquire(WALInsertLock, LW_EXCLUSIVE);

/* Critical section */
/* ... modify WAL buffers ... */

/* Release LWLock */
LWLockRelease(WALInsertLock);

/* Acquire in shared mode */
LWLockAcquire(BufMappingLock, LW_SHARED);
/* ... read buffer mapping ... */
LWLockRelease(BufMappingLock);
```

### 6.5 Heavyweight Locks

Heavyweight locks (also called "regular locks") are used for database objects like tables, rows, and transactions.

**Lock Modes** (in order of increasing restrictiveness):

1. **AccessShareLock**: SELECT
2. **RowShareLock**: SELECT FOR UPDATE/SHARE
3. **RowExclusiveLock**: INSERT, UPDATE, DELETE
4. **ShareUpdateExclusiveLock**: VACUUM, ANALYZE, CREATE INDEX CONCURRENTLY
5. **ShareLock**: CREATE INDEX
6. **ShareRowExclusiveLock**: (rarely used)
7. **ExclusiveLock**: REFRESH MATERIALIZED VIEW CONCURRENTLY
8. **AccessExclusiveLock**: ALTER TABLE, DROP TABLE, TRUNCATE, VACUUM FULL

**Lock Compatibility Matrix**:
```
         AS  RS  RE  SUE  S  SRE  E  AE
AS       ✓   ✓   ✓   ✓    ✓   ✓   ✓   ✗
RS       ✓   ✓   ✓   ✓    ✓   ✓   ✗   ✗
RE       ✓   ✓   ✓   ✓    ✗   ✗   ✗   ✗
SUE      ✓   ✓   ✓   ✗    ✗   ✗   ✗   ✗
S        ✓   ✓   ✗   ✗    ✓   ✗   ✗   ✗
SRE      ✓   ✓   ✗   ✗    ✗   ✗   ✗   ✗
E        ✓   ✗   ✗   ✗    ✗   ✗   ✗   ✗
AE       ✗   ✗   ✗   ✗    ✗   ✗   ✗   ✗

✓ = Compatible (locks can coexist)
✗ = Conflicts (one must wait)
```

### 6.6 Wait Events

Wait events allow monitoring what each backend is waiting for. Visible in `pg_stat_activity.wait_event` and `pg_stat_activity.wait_event_type`.

**Wait Event Types**:

- **Activity**: Idle, idle in transaction
- **BufferPin**: Waiting for buffer pin
- **Client**: Waiting for client to send/receive data
- **Extension**: Waiting in extension code
- **IO**: Waiting for I/O operation
- **IPC**: Waiting for another process
- **Lock**: Waiting for heavyweight lock
- **LWLock**: Waiting for lightweight lock
- **Timeout**: Waiting for timeout to expire

**Common Wait Events**:
```sql
-- View current waits
SELECT pid, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;

-- Example output:
  pid  | wait_event_type |     wait_event      | query
-------+-----------------+---------------------+----------------
  1234 | IO              | DataFileRead        | SELECT * FROM...
  1235 | Lock            | relation            | ALTER TABLE...
  1236 | Client          | ClientRead          | <idle>
  1237 | LWLock          | WALInsertLock       | INSERT INTO...
```

## 7. Client/Server Protocol

### 7.1 Connection Establishment

The PostgreSQL client/server protocol operates over TCP/IP or Unix domain sockets:

```
Connection Establishment:

Client                                    Server (Backend)
  │                                            │
  │ 1. TCP connect to port 5432                │
  ├───────────────────────────────────────────>│
  │                                            │
  │ 2. Send SSLRequest (optional)              │
  ├───────────────────────────────────────────>│
  │<───────────────────────────────────────────┤
  │ 3. Response: 'S' (SSL) or 'N' (no SSL)     │
  │                                            │
  │ [If SSL accepted, perform TLS handshake]   │
  │                                            │
  │ 4. Send StartupMessage                     │
  │    - Protocol version (3.0)                │
  │    - user=username                         │
  │    - database=dbname                       │
  │    - application_name=...                  │
  ├───────────────────────────────────────────>│
  │                                            │
  │                                            │ 5. Check pg_hba.conf
  │                                            │    Determine auth method
  │                                            │
  │<───────────────────────────────────────────┤
  │ 6. AuthenticationRequest                   │
  │    - AuthenticationOk (trust)              │
  │    - AuthenticationCleartextPassword       │
  │    - AuthenticationMD5Password             │
  │    - AuthenticationSASL                    │
  │    - etc.                                  │
  │                                            │
  │ 7. PasswordMessage (if needed)             │
  ├───────────────────────────────────────────>│
  │                                            │
  │                                            │ 8. Verify password
  │                                            │
  │<───────────────────────────────────────────┤
  │ 9. AuthenticationOk                        │
  │                                            │
  │<───────────────────────────────────────────┤
  │ 10. ParameterStatus messages               │
  │     - server_version                       │
  │     - server_encoding                      │
  │     - client_encoding                      │
  │     - etc.                                 │
  │                                            │
  │<───────────────────────────────────────────┤
  │ 11. BackendKeyData                         │
  │     - Process ID                           │
  │     - Secret key (for cancel requests)     │
  │                                            │
  │<───────────────────────────────────────────┤
  │ 12. ReadyForQuery                          │
  │     - Transaction status: 'I' (idle)       │
  │                                            │
  │ [Connection established, ready for queries]│
```

### 7.2 Message Format

All messages after startup follow this format:

```
┌────────────┬──────────────┬─────────────────────────┐
│ Type (1B)  │ Length (4B)  │ Message Data (variable) │
└────────────┴──────────────┴─────────────────────────┘

Type: Single character identifying message type
Length: Int32 - total length including length field itself
Data: Message-specific data
```

### 7.3 Message Types

**Client → Server**:

| Type | Name | Purpose |
|------|------|---------|
| **'Q'** | Query | Simple query (SQL string) |
| **'P'** | Parse | Parse prepared statement |
| **'B'** | Bind | Bind parameters to statement |
| **'E'** | Execute | Execute portal |
| **'D'** | Describe | Describe statement or portal |
| **'C'** | Close | Close statement or portal |
| **'S'** | Sync | Synchronize extended query |
| **'X'** | Terminate | Close connection |
| **'F'** | FunctionCall | Call function (fastpath) |
| **'d'** | CopyData | COPY data stream |
| **'c'** | CopyDone | COPY complete |
| **'f'** | CopyFail | COPY failed |

**Server → Client**:

| Type | Name | Purpose |
|------|------|---------|
| **'R'** | Authentication | Authentication request/response |
| **'K'** | BackendKeyData | Cancel key data |
| **'S'** | ParameterStatus | Runtime parameter status |
| **'Z'** | ReadyForQuery | Ready for new query |
| **'T'** | RowDescription | Row column descriptions |
| **'D'** | DataRow | Row data |
| **'C'** | CommandComplete | Query completed |
| **'E'** | ErrorResponse | Error occurred |
| **'N'** | NoticeResponse | Notice message |
| **'1'** | ParseComplete | Parse completed |
| **'2'** | BindComplete | Bind completed |
| **'3'** | CloseComplete | Close completed |
| **'I'** | EmptyQueryResponse | Empty query |
| **'s'** | PortalSuspended | Portal suspended (partial results) |
| **'n'** | NoData | No data returned |
| **'A'** | NotificationResponse | Asynchronous notification |
| **'d'** | CopyData | COPY data stream |
| **'c'** | CopyDone | COPY complete |
| **'G'** | CopyInResponse | Ready for COPY IN |
| **'H'** | CopyOutResponse | Starting COPY OUT |

### 7.4 Simple Query Protocol

The simple query protocol is used for single SQL statements:

```
Client                                    Server
  │                                            │
  │ Query('Q')                                 │
  │ "SELECT * FROM users WHERE id = 1"         │
  ├───────────────────────────────────────────>│
  │                                            │
  │                                            │ Parse query
  │                                            │ Plan query
  │                                            │ Execute query
  │                                            │
  │<───────────────────────────────────────────┤
  │ RowDescription('T')                        │
  │ - Field count: 3                           │
  │ - Field 1: "id", type=23 (int4)            │
  │ - Field 2: "name", type=25 (text)          │
  │ - Field 3: "email", type=25 (text)         │
  │                                            │
  │<───────────────────────────────────────────┤
  │ DataRow('D')                               │
  │ - Field count: 3                           │
  │ - Value 1: "1"                             │
  │ - Value 2: "Alice"                         │
  │ - Value 3: "alice@example.com"             │
  │                                            │
  │<───────────────────────────────────────────┤
  │ CommandComplete('C')                       │
  │ "SELECT 1"                                 │
  │                                            │
  │<───────────────────────────────────────────┤
  │ ReadyForQuery('Z')                         │
  │ Status: 'I' (idle)                         │
```

**Code Flow**:
```c
/* exec_simple_query from src/backend/tcop/postgres.c */
void
exec_simple_query(const char *query_string)
{
    /* Start transaction if not already in one */
    start_xact_command();

    /* Parse the query */
    parsetree_list = pg_parse_query(query_string);

    /* For each statement in the query string */
    foreach(parsetree_item, parsetree_list)
    {
        RawStmt *parsetree = lfirst_node(RawStmt, parsetree_item);

        /* Analyze and rewrite */
        querytree_list = pg_analyze_and_rewrite(parsetree, ...);

        /* Plan and execute */
        foreach(querytree_item, querytree_list)
        {
            Query *querytree = lfirst_node(Query, querytree_item);
            PlannedStmt *plan;

            /* Create execution plan */
            plan = pg_plan_query(querytree, ...);

            /* Execute plan */
            portal = CreatePortal(...);
            PortalDefineQuery(portal, ...);
            PortalStart(portal, ...);

            /* Fetch all rows and send to client */
            PortalRun(portal, FETCH_ALL, ...);

            /* Send CommandComplete */
            EndCommand(completionTag, DestRemote);
        }
    }

    /* Commit transaction */
    finish_xact_command();

    /* Send ReadyForQuery */
    ReadyForQuery(DestRemote);
}
```

### 7.5 Extended Query Protocol

The extended query protocol allows prepared statements, parameterized queries, and retrieving results in chunks:

```
Client                                    Server
  │                                            │
  │ Parse('P')                                 │
  │ - Statement name: "S1"                     │
  │ - Query: "SELECT * FROM users WHERE id=$1" │
  │ - Parameter types: [int4]                  │
  ├───────────────────────────────────────────>│
  │                                            │ Parse query
  │                                            │ Save prepared statement
  │<───────────────────────────────────────────┤
  │ ParseComplete('1')                         │
  │                                            │
  │ Bind('B')                                  │
  │ - Portal name: ""                          │
  │ - Statement name: "S1"                     │
  │ - Parameter values: [42]                   │
  ├───────────────────────────────────────────>│
  │                                            │ Bind parameters
  │<───────────────────────────────────────────┤
  │ BindComplete('2')                          │
  │                                            │
  │ Describe('D')                              │
  │ - Type: 'P' (portal)                       │
  │ - Name: ""                                 │
  ├───────────────────────────────────────────>│
  │<───────────────────────────────────────────┤
  │ RowDescription('T')                        │
  │ [field descriptions]                       │
  │                                            │
  │ Execute('E')                               │
  │ - Portal name: ""                          │
  │ - Max rows: 0 (all)                        │
  ├───────────────────────────────────────────>│
  │                                            │ Execute portal
  │<───────────────────────────────────────────┤
  │ DataRow('D') ... DataRow('D')              │
  │<───────────────────────────────────────────┤
  │ CommandComplete('C')                       │
  │                                            │
  │ Sync('S')                                  │
  ├───────────────────────────────────────────>│
  │<───────────────────────────────────────────┤
  │ ReadyForQuery('Z')                         │
```

**Advantages of Extended Protocol**:
- **Parameterization**: Prevents SQL injection, enables plan reuse
- **Type Safety**: Server knows parameter types in advance
- **Partial Results**: Can fetch N rows at a time (cursors)
- **Binary Format**: Can transfer data in binary (more efficient)
- **Pipelining**: Can send multiple messages before reading responses

## 8. Authentication

### 8.1 pg_hba.conf Rules

Authentication is controlled by `pg_hba.conf` (host-based authentication):

```
# TYPE  DATABASE    USER        ADDRESS         METHOD

# Local connections (Unix socket)
local   all         postgres                    trust
local   all         all                         peer

# IPv4 local connections
host    all         all         127.0.0.1/32    scram-sha-256
host    all         all         10.0.0.0/8      md5

# IPv6 local connections
host    all         all         ::1/128         scram-sha-256

# Replication connections
host    replication replicator  10.0.0.0/8      scram-sha-256

# Specific database/user combinations
host    production  webapp      192.168.1.0/24  scram-sha-256
host    analytics   analyst     192.168.2.0/24  ldap
```

**Fields**:
1. **TYPE**: Connection type (local, host, hostssl, hostnossl)
2. **DATABASE**: Which database(s) the rule applies to
3. **USER**: Which user(s) the rule applies to
4. **ADDRESS**: Client IP address range (for host connections)
5. **METHOD**: Authentication method to use

### 8.2 Authentication Methods

| Method | Description | Security | Use Case |
|--------|-------------|----------|----------|
| **trust** | No authentication | None | Development only |
| **reject** | Reject connection | N/A | Explicitly block access |
| **scram-sha-256** | SCRAM-SHA-256 challenge | Strong | **Recommended for production** |
| **md5** | MD5 password hash | Medium | Legacy (deprecated) |
| **password** | Plaintext password | Weak | Never use over network |
| **peer** | OS username match | Medium | Local connections only |
| **ident** | Remote ident server | Weak | Legacy systems |
| **gss** | GSSAPI/Kerberos | Strong | Enterprise environments |
| **sspi** | Windows SSPI | Strong | Windows Active Directory |
| **ldap** | LDAP server | Medium | Centralized auth |
| **radius** | RADIUS server | Medium | Network access control |
| **cert** | SSL client certificate | Strong | Certificate-based auth |
| **pam** | PAM (Pluggable Auth) | Varies | System authentication |

### 8.3 SCRAM-SHA-256 Authentication Flow

SCRAM (Salted Challenge Response Authentication Mechanism) is the most secure password-based method:

```
Client                                    Server
  │                                            │
  │ 1. StartupMessage                          │
  │    user=alice, database=mydb               │
  ├───────────────────────────────────────────>│
  │                                            │
  │                                            │ Check pg_hba.conf
  │                                            │ Method: scram-sha-256
  │                                            │
  │<───────────────────────────────────────────┤
  │ 2. AuthenticationSASL                      │
  │    Mechanisms: [SCRAM-SHA-256]             │
  │                                            │
  │ 3. SASLInitialResponse                     │
  │    Selected: SCRAM-SHA-256                 │
  │    Client nonce: <random>                  │
  ├───────────────────────────────────────────>│
  │                                            │
  │                                            │ Generate server nonce
  │                                            │ Get stored password hash
  │                                            │
  │<───────────────────────────────────────────┤
  │ 4. AuthenticationSASLContinue              │
  │    Server nonce: <random>                  │
  │    Salt: <from stored password>            │
  │    Iterations: 4096                        │
  │                                            │
  │ Derive key from password                   │
  │ Create client proof                        │
  │                                            │
  │ 5. SASLResponse                            │
  │    Client proof: <proof>                   │
  ├───────────────────────────────────────────>│
  │                                            │
  │                                            │ Verify client proof
  │                                            │ Generate server signature
  │                                            │
  │<───────────────────────────────────────────┤
  │ 6. AuthenticationSASLFinal                 │
  │    Server signature: <signature>           │
  │                                            │
  │ Verify server signature                    │
  │                                            │
  │<───────────────────────────────────────────┤
  │ 7. AuthenticationOk                        │
  │                                            │
  │ [Continue with connection setup]           │
```

**Password Storage** (in `pg_authid.rolpassword`):
```
SCRAM-SHA-256$<iterations>:<salt>$<StoredKey>:<ServerKey>
```

**Security Properties**:
- Password never sent over network
- Salt prevents rainbow table attacks
- Iterations (4096) make brute force expensive
- Server proves it knows password (mutual authentication)
- Resistant to replay attacks (nonces)

### 8.4 SSL/TLS Encryption

PostgreSQL supports SSL/TLS for encrypted connections:

**Server Configuration** (`postgresql.conf`):
```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'           # For client certificate verification
ssl_crl_file = 'root.crl'          # Certificate revocation list

# Cipher configuration
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
```

**Client Connection**:
```bash
# Require SSL
psql "host=db.example.com sslmode=require dbname=mydb user=alice"

# Verify server certificate
psql "host=db.example.com sslmode=verify-full sslrootcert=root.crt dbname=mydb user=alice"

# Client certificate authentication
psql "host=db.example.com sslcert=client.crt sslkey=client.key dbname=mydb user=alice"
```

**SSL Modes**:
- `disable`: No SSL
- `allow`: Try SSL, fall back to plain
- `prefer`: Try SSL first (default)
- `require`: Require SSL (don't verify certificate)
- `verify-ca`: Require SSL, verify CA
- `verify-full`: Require SSL, verify CA and hostname

## 9. Shutdown Modes

PostgreSQL supports three shutdown modes, each with different tradeoffs between speed and safety.

### 9.1 Smart Shutdown (SIGTERM)

**Command**: `pg_ctl stop -m smart` or `kill -TERM <postmaster_pid>`

**Behavior**:
1. Postmaster stops accepting new connections
2. Existing client sessions continue normally
3. Waits for all clients to disconnect
4. Once all clients disconnected:
   - Performs checkpoint
   - Shuts down auxiliary processes
   - Exits cleanly

**Use Case**: Graceful shutdown when you can wait for clients

**Sequence**:
```
1. Postmaster receives SIGTERM
2. Postmaster stops listening on sockets
3. Postmaster waits for all backends to exit
   [Could wait indefinitely if client doesn't disconnect]
4. Postmaster signals auxiliary processes to shutdown
5. Checkpointer performs final checkpoint
6. All processes exit
7. Postmaster exits
```

**Process State**:
```bash
# During smart shutdown
$ ps aux | grep postgres
postgres  1234  postmaster (shutting down)
postgres  1235  postgres: alice mydb [waiting for clients]
postgres  1236  postgres: bob testdb [waiting for clients]
```

### 9.2 Fast Shutdown (SIGINT)

**Command**: `pg_ctl stop -m fast` or `kill -INT <postmaster_pid>`

**Behavior**:
1. Postmaster stops accepting new connections
2. Sends SIGTERM to all backends (disconnects clients)
3. Waits for backends to exit cleanly
4. Performs checkpoint
5. Shuts down cleanly

**Use Case**: **Standard shutdown method** - fast but safe

**Sequence**:
```
1. Postmaster receives SIGINT
2. Postmaster stops listening on sockets
3. Postmaster sends SIGTERM to all child processes
4. Backends:
   - Abort current transactions
   - Close client connections
   - Release resources
   - Exit
5. Checkpointer performs final checkpoint
6. All auxiliary processes shutdown
7. Postmaster exits
```

**Client Experience**:
```
mydb=> SELECT * FROM large_table;
FATAL:  terminating connection due to administrator command
server closed the connection unexpectedly
```

### 9.3 Immediate Shutdown (SIGQUIT)

**Command**: `pg_ctl stop -m immediate` or `kill -QUIT <postmaster_pid>`

**Behavior**:
1. Postmaster sends SIGQUIT to all children
2. All processes exit immediately without cleanup
3. No checkpoint performed
4. **Requires crash recovery on next startup**

**Use Case**: Emergency only—system is unresponsive or corrupted

**Sequence**:
```
1. Postmaster receives SIGQUIT
2. Postmaster sends SIGQUIT to all children
3. All processes exit immediately
4. Postmaster exits
5. No checkpoint, no cleanup
6. Next startup will perform crash recovery
```

**Warning**: Immediate shutdown is equivalent to a crash. Use only when:
- Database is hung and not responding
- Corruption suspected
- System is shutting down and you can't wait
- Testing crash recovery procedures

**Recovery After Immediate Shutdown**:
```
$ pg_ctl start
waiting for server to start....
LOG:  database system was interrupted; last known up at 2025-11-19 10:30:15 UTC
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/1234568
LOG:  invalid record length at 0/1234890: wanted 24, got 0
LOG:  redo done at 0/1234850
LOG:  checkpoint starting: end-of-recovery immediate
LOG:  checkpoint complete: wrote 42 buffers (0.3%); 0 WAL file(s) added, 0 removed, 1 recycled
LOG:  database system is ready to accept connections
```

### 9.4 Shutdown Comparison

| Aspect | Smart | Fast | Immediate |
|--------|-------|------|-----------|
| **New connections** | Rejected | Rejected | N/A (instant exit) |
| **Existing sessions** | Continue | Terminated | Terminated |
| **Wait for clients** | Yes | No | No |
| **Checkpoint** | Yes | Yes | No |
| **Recovery needed** | No | No | **Yes** |
| **Speed** | Slow (indefinite) | Fast (seconds) | Instant |
| **Safety** | Safest | Safe | Unsafe |
| **Recommended use** | Maintenance | **Standard** | Emergency only |

## 10. Process State Diagrams

### 10.1 Complete Backend State Machine

```
Backend Process Lifecycle State Machine:

┌─────────────────┐
│  NOT_STARTED    │
└────────┬────────┘
         │
         │ fork()
         │
         ▼
┌─────────────────┐
│   FORKED        │  Process created, initializing
└────────┬────────┘
         │
         │ Setup signal handlers, attach shared memory
         │
         ▼
┌─────────────────┐
│ AUTHENTICATING  │  Reading startup packet, checking pg_hba.conf
└────────┬────────┘
         │
         │ Authentication success
         │
         ▼
┌─────────────────┐
│ INITIALIZING    │  Loading database, initializing subsystems
└────────┬────────┘
         │
         │ Send ReadyForQuery
         │
         ▼
┌─────────────────┐
│      IDLE       │◄──────────────────────────┐
└────────┬────────┘                           │
         │                                    │
         │ Receive Query                      │
         │                                    │
         ▼                                    │
┌─────────────────┐                           │
│    RUNNING      │  Executing query          │
└────────┬────────┘                           │
         │                                    │
         ├───────► Query complete ────────────┤
         │                                    │
         │ BEGIN                              │
         │                                    │
         ▼                                    │
┌─────────────────────────┐                   │
│ IDLE_IN_TRANSACTION     │                   │
└────────┬────────────────┘                   │
         │                                    │
         │ Execute statement                  │
         │                                    │
         ▼                                    │
┌───────────────────────────┐                 │
│ RUNNING_IN_TRANSACTION    │                 │
└────────┬──────────────────┘                 │
         │                                    │
         ├──► Statement OK ───────────────────┤
         │                                    │
         │ Error                              │
         │                                    │
         ▼                                    │
┌──────────────────────────────────┐          │
│ IDLE_IN_TRANSACTION_ABORTED      │          │
│ (must ROLLBACK)                  │          │
└────────┬─────────────────────────┘          │
         │                                    │
         │ ROLLBACK                           │
         │                                    │
         └────────────────────────────────────┘

Additional States:

┌─────────────────┐
│  FASTPATH       │  Executing function via fastpath protocol
└─────────────────┘

┌─────────────────┐
│  COPY_IN        │  Receiving COPY data from client
└─────────────────┘

┌─────────────────┐
│  COPY_OUT       │  Sending COPY data to client
└─────────────────┘

┌─────────────────┐
│  COPY_BOTH      │  Bidirectional COPY (replication)
└─────────────────┘

┌─────────────────┐
│ PORTAL_RUNNING  │  Executing portal (cursor)
└─────────────────┘

┌─────────────────┐
│   DISABLED      │  Backend shutting down, no new commands
└─────────────────┘

┌─────────────────┐
│   TERMINATED    │  Process exited
└─────────────────┘
```

### 10.2 Postmaster State Machine

```
Postmaster Lifecycle:

┌──────────────┐
│   STARTUP    │  Reading config, creating shared memory
└──────┬───────┘
       │
       │ Initialization complete
       │
       ▼
┌──────────────┐
│   RECOVERY   │  Startup process performing crash/archive recovery
└──────┬───────┘
       │
       │ Recovery complete
       │
       ▼
┌──────────────┐
│   RUNNING    │◄───────────────┐  Normal operation
└──────┬───────┘                │
       │                        │
       │ Receive SIGHUP         │
       │                        │
       ▼                        │
┌──────────────┐                │
│   RELOADING  │  Re-reading config, signaling children
└──────┬───────┘                │
       │                        │
       └────────────────────────┘

From RUNNING:

       │ Receive SIGTERM (smart)
       │
       ▼
┌──────────────────┐
│ SMART_SHUTDOWN   │  Waiting for clients to disconnect
└──────┬───────────┘
       │
       │ All clients gone
       │
       ▼
┌──────────────────┐
│   CHECKPOINTING  │  Final checkpoint
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│   SHUTDOWN       │  Stopping all processes
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│     EXITED       │
└──────────────────┘

From RUNNING:

       │ Receive SIGINT (fast)
       │
       ▼
┌──────────────────┐
│  FAST_SHUTDOWN   │  Terminating all backends
└──────┬───────────┘
       │
       │ All backends terminated
       │
       └─────► CHECKPOINTING ─────► SHUTDOWN ─────► EXITED

From RUNNING:

       │ Receive SIGQUIT (immediate)
       │
       ▼
┌──────────────────┐
│IMMEDIATE_SHUTDOWN│  Killing all processes
└──────┬───────────┘
       │
       │ (no checkpoint)
       │
       ▼
┌──────────────────┐
│     EXITED       │
└──────────────────┘

From RUNNING:

       │ Backend crash detected
       │
       ▼
┌──────────────────┐
│ CRASH_RECOVERY   │  Emergency: kill all backends, restart
└──────┬───────────┘
       │
       │ All backends terminated
       │
       ▼
┌──────────────────┐
│   RECOVERY       │  Startup process performs crash recovery
└──────────────────┘
       │
       │ Recovery complete
       │
       ▼
┌──────────────────┐
│    RUNNING       │  Back to normal operation
└──────────────────┘
```

## 11. Implementation Details

### 11.1 Key Source Files

**Postmaster and Process Management**:
- `src/backend/postmaster/postmaster.c`: Main postmaster code
- `src/backend/postmaster/fork_process.c`: Process forking
- `src/backend/postmaster/bgwriter.c`: Background writer
- `src/backend/postmaster/checkpointer.c`: Checkpointer process
- `src/backend/postmaster/walwriter.c`: WAL writer
- `src/backend/postmaster/autovacuum.c`: Autovacuum launcher/workers
- `src/backend/postmaster/pgarch.c`: Archiver process
- `src/backend/postmaster/pgstat.c`: Statistics collector
- `src/backend/postmaster/syslogger.c`: Logging process

**Backend Execution**:
- `src/backend/tcop/postgres.c`: Main backend loop (PostgresMain)
- `src/backend/tcop/pquery.c`: Portal and query execution
- `src/backend/tcop/utility.c`: Utility command execution

**Client/Server Protocol**:
- `src/backend/libpq/pqcomm.c`: Communication functions
- `src/backend/libpq/pqformat.c`: Message formatting
- `src/backend/libpq/auth.c`: Authentication
- `src/backend/libpq/hba.c`: pg_hba.conf parsing
- `src/interfaces/libpq/`: Client library

**Shared Memory**:
- `src/backend/storage/ipc/ipci.c`: Shared memory initialization
- `src/backend/storage/ipc/shmem.c`: Shared memory management
- `src/backend/storage/buffer/buf_init.c`: Buffer pool initialization
- `src/backend/storage/buffer/bufmgr.c`: Buffer management

**IPC Mechanisms**:
- `src/backend/storage/ipc/latch.c`: Latch implementation
- `src/backend/storage/ipc/procsignal.c`: Process signaling
- `src/backend/storage/lmgr/spin.c`: Spinlocks
- `src/backend/storage/lmgr/lwlock.c`: Lightweight locks
- `src/backend/storage/lmgr/lock.c`: Heavyweight locks

**Replication**:
- `src/backend/replication/walsender.c`: WAL sender
- `src/backend/replication/walreceiver.c`: WAL receiver
- `src/backend/replication/logical/launcher.c`: Logical replication

### 11.2 Key Data Structures

**PGPROC** - Represents a process in shared memory:
```c
/* src/include/storage/proc.h */
typedef struct PGPROC
{
    /* Process identification */
    int         pgprocno;         /* Index in PGPROC array */

    /* Transaction info */
    TransactionId xid;            /* Transaction ID (if running) */
    TransactionId xmin;           /* Minimum XID in snapshot */

    /* Lock management */
    LOCK_METHOD lockMethodTable;  /* Lock method for this proc */
    LOCKMASK    heldLocks;        /* Bitmask of lock types held */
    SHM_QUEUE   myProcLocks[NUM_LOCK_PARTITIONS]; /* Locks held */

    /* Wait information */
    WaitEventSet *waitEventSet;   /* What we're waiting for */
    uint32      wait_event_info;  /* Wait event details */

    /* Signaling */
    Latch       procLatch;        /* For waking up process */

    /* Process metadata */
    Oid         databaseId;       /* Database OID */
    Oid         roleId;           /* Role OID */
    bool        isBackgroundWorker;

    /* Miscellaneous */
    int         pgxactoff;        /* Offset in ProcGlobal->allProcs */
    BackendId   backendId;        /* Backend ID (1..MaxBackends) */
} PGPROC;
```

**Port** - Connection information:
```c
/* src/include/libpq/libpq-be.h */
typedef struct Port
{
    /* Socket and address */
    pgsocket    sock;             /* Socket file descriptor */
    SockAddr    laddr;            /* Local address */
    SockAddr    raddr;            /* Remote address */

    /* Connection metadata */
    char        *remote_host;     /* Hostname of client */
    char        *remote_hostname; /* Reverse DNS lookup result */
    char        *remote_port;     /* Port on client */

    /* Authentication */
    char        *database_name;   /* Database requested */
    char        *user_name;       /* User name */
    char        *cmdline_options; /* Command-line options */

    /* SSL */
    void        *ssl;             /* SSL structure (if SSL) */
    bool        ssl_in_use;       /* SSL connection active */

    /* GSSAPI */
    void        *gss;             /* GSSAPI structure */

    /* Protocol version */
    ProtocolVersion proto;        /* FE/BE protocol version */

    /* pg_hba match */
    HbaLine     *hba;             /* Matched pg_hba.conf line */
} Port;
```

**BufferDesc** - Buffer pool entry:
```c
/* src/include/storage/buf_internals.h */
typedef struct BufferDesc
{
    BufferTag   tag;              /* ID of page in buffer */
    int         buf_id;           /* Buffer index (0..NBuffers-1) */

    /* State and reference count (atomic) */
    pg_atomic_uint32 state;

    /* Waiting processes */
    int         wait_backend_pid;

    /* Header spinlock */
    slock_t     buf_hdr_lock;

    /* Free list link */
    int         freeNext;
} BufferDesc;
```

### 11.3 Process Title (ps Display)

PostgreSQL sets descriptive process titles visible in `ps` and `top`:

```bash
$ ps aux | grep postgres
postgres  1234  postmaster -D /var/lib/pgsql/data
postgres  1235  postgres: checkpointer
postgres  1236  postgres: background writer
postgres  1237  postgres: walwriter
postgres  1238  postgres: autovacuum launcher
postgres  1239  postgres: archiver
postgres  1240  postgres: stats collector
postgres  1241  postgres: logical replication launcher
postgres  1242  postgres: alice mydb [local] idle
postgres  1243  postgres: bob testdb 192.168.1.100(54321) SELECT
postgres  1244  postgres: carol analytics 10.0.0.5(12345) idle in transaction
postgres  1245  postgres: autovacuum worker process mydb
postgres  1246  postgres: walsender replicator 10.0.0.10(5433) streaming 0/12345678
```

**Format**: `postgres: <user> <database> <host> <state> [query]`

**Code**:
```c
/* src/backend/utils/misc/ps_status.c */
void
set_ps_display(const char *activity)
{
    char *display_buffer;

    /* Build display string */
    display_buffer = psprintf("postgres: %s %s %s %s",
                              MyProcPort->user_name,
                              MyProcPort->database_name,
                              get_backend_state_string(),
                              activity);

    /* Set process title (platform-specific) */
    setproctitle("%s", display_buffer);
}
```

## 12. Cross-References and Related Topics

### Related Encyclopedia Chapters

- **Chapter 3: Architecture Overview**: High-level system architecture and component interaction
- **Chapter 4: Storage Management**: How processes interact with disk storage, buffer management
- **Chapter 6: Transaction Management**: MVCC, transaction ID assignment, locking mechanisms
- **Chapter 7: Write-Ahead Logging**: WAL generation, WAL sender/receiver protocols
- **Chapter 8: Replication**: Physical and logical replication process architecture
- **Chapter 10: Query Processing**: Backend query execution, parallel query workers
- **Chapter 11: Concurrency Control**: Lock management, deadlock detection, isolation levels
- **Chapter 15: Connection Pooling**: External tools (PgBouncer, pgpool) for process management

### Key System Views

Monitor process activity using these system views:

```sql
-- Active processes
SELECT * FROM pg_stat_activity;

-- Replication status
SELECT * FROM pg_stat_replication;

-- WAL receiver status (on standby)
SELECT * FROM pg_stat_wal_receiver;

-- Background writer statistics
SELECT * FROM pg_stat_bgwriter;

-- Archiver statistics
SELECT * FROM pg_stat_archiver;

-- Current process information
SELECT pg_backend_pid();              -- My backend PID
SELECT pg_postmaster_start_time();    -- When postmaster started
SELECT pg_conf_load_time();           -- Last config reload

-- Cancel or terminate backends
SELECT pg_cancel_backend(pid);        -- Cancel query
SELECT pg_terminate_backend(pid);     -- Terminate connection
```

### Performance Tuning

Key configuration parameters affecting process behavior:

```ini
# Connection and authentication
max_connections = 100
superuser_reserved_connections = 3
listen_addresses = '*'
port = 5432

# Resource usage (per backend)
work_mem = 4MB                    # Per-operation memory
maintenance_work_mem = 64MB       # Vacuum, CREATE INDEX memory
temp_buffers = 8MB                # Temp table buffers

# Background writer
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0

# Checkpointing
checkpoint_timeout = 5min
max_wal_size = 1GB
checkpoint_completion_target = 0.9

# Autovacuum
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min

# WAL writer
wal_writer_delay = 200ms
wal_writer_flush_after = 1MB

# Parallel query
max_parallel_workers_per_gather = 2
max_parallel_workers = 8
parallel_setup_cost = 1000
parallel_tuple_cost = 0.1
```

## Conclusion

PostgreSQL's multi-process architecture is a carefully designed system that provides robust fault isolation, security, and portability. The postmaster serves as a supervisor that never touches shared memory, ensuring it can always detect and recover from backend crashes. Backend processes follow a well-defined lifecycle and state machine, handling client queries through a sophisticated protocol. Auxiliary processes perform essential maintenance tasks, from checkpointing to autovacuum to WAL archiving.

The shared memory architecture enables efficient communication between processes while maintaining strong isolation boundaries. Various IPC mechanisms—signals, latches, spinlocks, LWLocks, and heavyweight locks—provide the necessary coordination and synchronization. The client/server protocol supports both simple and extended query modes, enabling everything from basic SQL queries to complex prepared statements and bulk data transfer.

Understanding this process architecture is fundamental to administering, tuning, and developing with PostgreSQL. It explains observable behavior like connection limits, process listings, and shutdown modes. It also provides the foundation for understanding more advanced topics like replication, parallel query execution, and high availability.

---

**See Also**:
- PostgreSQL Documentation: [Server Processes](https://www.postgresql.org/docs/current/server-processes.html)
- PostgreSQL Documentation: [Client/Server Protocol](https://www.postgresql.org/docs/current/protocol.html)
- PostgreSQL Source: `src/backend/postmaster/README`
- PostgreSQL Source: `src/backend/tcop/README`
