# Chapter 4: Replication and Recovery Systems

## Overview

PostgreSQL's replication and recovery systems form the foundation of high availability, disaster recovery, and data protection in modern database deployments. These systems enable databases to maintain multiple synchronized copies, recover from failures, and provide continuous availability through sophisticated Write-Ahead Log (WAL) based mechanisms.

This chapter explores the architectural components, algorithms, and data structures that implement PostgreSQL's replication capabilities, from low-level WAL streaming to high-level logical replication, along with comprehensive recovery mechanisms including crash recovery, Point-In-Time Recovery (PITR), and hot standby operations.

---

## 1. WAL-Based Streaming Replication

### 1.1 Architecture Overview

Streaming replication in PostgreSQL operates through a producer-consumer model where a primary server (the WAL sender) streams Write-Ahead Log records to one or more standby servers (WAL receivers). This architecture provides real-time replication with minimal latency and supports both synchronous and asynchronous replication modes.

The core components are:
- **WalSender**: Process on the primary that streams WAL data
- **WalReceiver**: Process on the standby that receives WAL data
- **Replication Slots**: Persistent markers tracking replication progress
- **WAL Archive**: Optional persistent WAL storage for disaster recovery

### 1.2 WalSender Architecture

The WalSender process manages outbound replication connections. Each replication connection has a dedicated WalSender process that reads WAL from the primary's WAL buffers or files and transmits it to standbys.

**WalSnd Structure** (`src/include/replication/walsender_private.h:41-79`):

```c
typedef struct WalSnd
{
    pid_t       pid;            /* this walsender's PID, or 0 if not active */

    WalSndState state;          /* this walsender's state */
    XLogRecPtr  sentPtr;        /* WAL has been sent up to this point */
    bool        needreload;     /* does currently-open file need to be reloaded? */

    /*
     * The xlog locations that have been written, flushed, and applied by
     * standby-side. These may be invalid if the standby-side has not offered
     * values yet.
     */
    XLogRecPtr  write;
    XLogRecPtr  flush;
    XLogRecPtr  apply;

    /* Measured lag times, or -1 for unknown/none. */
    TimeOffset  writeLag;
    TimeOffset  flushLag;
    TimeOffset  applyLag;

    /*
     * The priority order of the standby managed by this WALSender, as listed
     * in synchronous_standby_names, or 0 if not-listed.
     */
    int         sync_standby_priority;

    /* Protects shared variables in this structure. */
    slock_t     mutex;

    /*
     * Timestamp of the last message received from standby.
     */
    TimestampTz replyTime;

    ReplicationKind kind;
} WalSnd;
```

The `WalSnd` structure tracks critical replication state:

- **Progress Tracking**: `sentPtr`, `write`, `flush`, and `apply` track WAL propagation through the pipeline
- **Lag Monitoring**: `writeLag`, `flushLag`, and `applyLag` measure replication delay at each stage
- **Synchronous Replication**: `sync_standby_priority` determines which standbys participate in synchronous commits
- **Concurrency Control**: `mutex` spinlock protects concurrent access to shared state

**WalSender States** (`src/include/replication/walsender_private.h:24-31`):

```c
typedef enum WalSndState
{
    WALSNDSTATE_STARTUP = 0,
    WALSNDSTATE_BACKUP,
    WALSNDSTATE_CATCHUP,
    WALSNDSTATE_STREAMING,
    WALSNDSTATE_STOPPING,
} WalSndState;
```

State transitions:
1. **STARTUP**: Initial state, establishing connection
2. **BACKUP**: Transferring base backup (pg_basebackup)
3. **CATCHUP**: Sending historical WAL to bring standby up to date
4. **STREAMING**: Normal streaming replication mode
5. **STOPPING**: Graceful shutdown in progress

### 1.3 WalReceiver Architecture

The WalReceiver is a background process on standby servers that connects to the primary's WalSender, receives WAL data, and writes it to local WAL files for replay by the startup process.

**WalRcvData Structure** (`src/include/replication/walreceiver.h:57-163`):

```c
typedef struct
{
    /*
     * Currently active walreceiver process's proc number and PID.
     */
    ProcNumber  procno;
    pid_t       pid;

    /* Its current state */
    WalRcvState walRcvState;
    ConditionVariable walRcvStoppedCV;

    /* Its start time */
    pg_time_t   startTime;

    /*
     * receiveStart and receiveStartTLI indicate the first byte position and
     * timeline that will be received.
     */
    XLogRecPtr  receiveStart;
    TimeLineID  receiveStartTLI;

    /*
     * flushedUpto-1 is the last byte position that has already been received,
     * and receivedTLI is the timeline it came from.
     */
    XLogRecPtr  flushedUpto;
    TimeLineID  receivedTLI;

    /*
     * latestChunkStart is the starting byte position of the current "batch"
     * of received WAL.
     */
    XLogRecPtr  latestChunkStart;

    /* Time of send and receive of any message received. */
    TimestampTz lastMsgSendTime;
    TimestampTz lastMsgReceiptTime;

    /* Latest reported end of WAL on the sender */
    XLogRecPtr  latestWalEnd;
    TimestampTz latestWalEndTime;

    /* connection string; initially set to connect to the primary */
    char        conninfo[MAXCONNINFO];

    /* Host name and port number of the active replication connection. */
    char        sender_host[NI_MAXHOST];
    int         sender_port;

    /* replication slot name */
    char        slotname[NAMEDATALEN];

    /* If it's a temporary replication slot */
    bool        is_temp_slot;

    bool        ready_to_display;

    slock_t     mutex;          /* locks shared variables shown above */

    /*
     * Like flushedUpto, but advanced after writing and before flushing,
     * without the need to acquire the spin lock.
     */
    pg_atomic_uint64 writtenUpto;

    sig_atomic_t force_reply;   /* used as a bool */
} WalRcvData;
```

**WalReceiver States** (`src/include/replication/walreceiver.h:45-54`):

```c
typedef enum
{
    WALRCV_STOPPED,             /* stopped and mustn't start up again */
    WALRCV_STARTING,            /* launched, but the process hasn't initialized yet */
    WALRCV_STREAMING,           /* walreceiver is streaming */
    WALRCV_WAITING,             /* stopped streaming, waiting for orders */
    WALRCV_RESTARTING,          /* asked to restart streaming */
    WALRCV_STOPPING,            /* requested to stop, but still running */
} WalRcvState;
```

### 1.4 Replication Protocol Flow

The replication protocol implements a streaming COPY protocol with feedback:

1. **Connection Establishment**: Standby connects to primary with `replication=true`
2. **Slot Identification**: Standby specifies replication slot (optional but recommended)
3. **Start Position Negotiation**: Standby sends `START_REPLICATION` with desired LSN
4. **WAL Streaming**: Primary sends WAL records in CopyData messages
5. **Standby Feedback**: Standby sends periodic status updates with `write`, `flush`, `apply` positions
6. **Flow Control**: Primary uses feedback to manage WAL retention and synchronous commits

**Stream Options** (`src/include/replication/walreceiver.h:167-192`):

```c
typedef struct
{
    bool        logical;        /* True if logical replication, false if physical */
    char       *slotname;       /* Name of the replication slot or NULL */
    XLogRecPtr  startpoint;     /* LSN of starting point */

    union
    {
        struct
        {
            TimeLineID  startpointTLI;  /* Starting timeline */
        }           physical;
        struct
        {
            uint32      proto_version;  /* Logical protocol version */
            List       *publication_names;
            bool        binary;         /* Ask publisher to use binary */
            char       *streaming_str;  /* Streaming of large transactions */
            bool        twophase;       /* Two-phase transactions */
            char       *origin;         /* Publish data from specified origin */
        }           logical;
    }           proto;
} WalRcvStreamOptions;
```

---

## 2. Logical Replication and Logical Decoding

### 2.1 Logical Replication Overview

Logical replication decodes WAL records into logical change events (INSERT, UPDATE, DELETE) that can be selectively replicated to subscribers. Unlike physical replication which replicates exact byte-level changes, logical replication operates at the table/row level and supports:

- **Selective Replication**: Replicate specific tables or databases
- **Version Independence**: Different PostgreSQL versions can replicate
- **Data Transformation**: Subscribers can have different schemas, indexes, or constraints
- **Multi-Master Capabilities**: Bidirectional replication configurations

### 2.2 LogicalDecodingContext

The `LogicalDecodingContext` is the central coordinator for logical decoding operations.

**Structure Definition** (`src/include/replication/logical.h:33-115`):

```c
typedef struct LogicalDecodingContext
{
    /* memory context this is all allocated in */
    MemoryContext context;

    /* The associated replication slot */
    ReplicationSlot *slot;

    /* infrastructure pieces for decoding */
    XLogReaderState *reader;
    struct ReorderBuffer *reorder;
    struct SnapBuild *snapshot_builder;

    /*
     * Marks the logical decoding context as fast forward decoding one.
     */
    bool        fast_forward;

    OutputPluginCallbacks callbacks;
    OutputPluginOptions options;

    /* User specified options */
    List       *output_plugin_options;

    /* User-Provided callback for writing/streaming out data. */
    LogicalOutputPluginWriterPrepareWrite prepare_write;
    LogicalOutputPluginWriterWrite write;
    LogicalOutputPluginWriterUpdateProgress update_progress;

    /* Output buffer. */
    StringInfo  out;

    /* Private data pointer of the output plugin. */
    void       *output_plugin_private;

    /* Private data pointer for the data writer. */
    void       *output_writer_private;

    /* Does the output plugin support streaming, and is it enabled? */
    bool        streaming;

    /* Does the output plugin support two-phase decoding, and is it enabled? */
    bool        twophase;

    /* Is two-phase option given by output plugin? */
    bool        twophase_opt_given;

    /* State for writing output. */
    bool        accept_writes;
    bool        prepared_write;
    XLogRecPtr  write_location;
    TransactionId write_xid;
    bool        end_xact;

    /* Do we need to process any change in fast_forward mode? */
    bool        processing_required;
} LogicalDecodingContext;
```

Key components:

- **ReorderBuffer**: Assembles concurrent transactions into commit order
- **SnapBuild**: Builds consistent snapshots for decoding
- **XLogReaderState**: Reads and parses WAL records
- **Output Plugin**: Formats decoded changes for transmission

### 2.3 ReorderBuffer: Transaction Reassembly

The ReorderBuffer is a sophisticated component that solves a critical problem in logical decoding: WAL records from concurrent transactions are interleaved, but subscribers need changes in transaction commit order.

**ReorderBuffer Change Types** (`src/include/replication/reorderbuffer.h:50-64`):

```c
typedef enum ReorderBufferChangeType
{
    REORDER_BUFFER_CHANGE_INSERT,
    REORDER_BUFFER_CHANGE_UPDATE,
    REORDER_BUFFER_CHANGE_DELETE,
    REORDER_BUFFER_CHANGE_MESSAGE,
    REORDER_BUFFER_CHANGE_INVALIDATION,
    REORDER_BUFFER_CHANGE_INTERNAL_SNAPSHOT,
    REORDER_BUFFER_CHANGE_INTERNAL_COMMAND_ID,
    REORDER_BUFFER_CHANGE_INTERNAL_TUPLECID,
    REORDER_BUFFER_CHANGE_INTERNAL_SPEC_INSERT,
    REORDER_BUFFER_CHANGE_INTERNAL_SPEC_CONFIRM,
    REORDER_BUFFER_CHANGE_INTERNAL_SPEC_ABORT,
    REORDER_BUFFER_CHANGE_TRUNCATE,
} ReorderBufferChangeType;
```

**ReorderBuffer Change Structure** (`src/include/replication/reorderbuffer.h:76-150`):

```c
typedef struct ReorderBufferChange
{
    XLogRecPtr  lsn;

    /* The type of change. */
    ReorderBufferChangeType action;

    /* Transaction this change belongs to. */
    struct ReorderBufferTXN *txn;

    RepOriginId origin_id;

    union
    {
        /* Old, new tuples when action == *_INSERT|UPDATE|DELETE */
        struct
        {
            RelFileLocator rlocator;
            bool        clear_toast_afterwards;
            HeapTuple   oldtuple;   /* valid for DELETE || UPDATE */
            HeapTuple   newtuple;   /* valid for INSERT || UPDATE */
        }           tp;

        /* Truncate data */
        struct
        {
            Size        nrelids;
            bool        cascade;
            bool        restart_seqs;
            Oid        *relids;
        }           truncate;

        /* Message with arbitrary data. */
        struct
        {
            char       *prefix;
            Size        message_size;
            char       *message;
        }           msg;

        /* New snapshot for catalog changes */
        Snapshot    snapshot;

        /* New command id for existing snapshot */
        CommandId   command_id;

        /* Catalog tuple metadata */
        struct
        {
            RelFileLocator locator;
            ItemPointerData tid;
            CommandId   cmin;
            CommandId   cmax;
            CommandId   combocid;
        }           tuplecid;
    };
} ReorderBufferChange;
```

**Algorithm**:

1. **WAL Scanning**: Read WAL records sequentially
2. **Transaction Buffering**: Group changes by TransactionId
3. **Memory Management**: Spill large transactions to disk when exceeding `logical_decoding_work_mem`
4. **Commit Ordering**: When transaction commits, replay all its changes in order
5. **Snapshot Application**: Use historical snapshots to determine tuple visibility

### 2.4 Output Plugins

Output plugins transform decoded changes into wire format. PostgreSQL provides `pgoutput` for native logical replication, and the plugin API allows custom formats.

**Plugin Interface**:
- `startup_cb`: Initialize plugin state
- `begin_cb`: Transaction begin
- `change_cb`: Individual row change (INSERT/UPDATE/DELETE)
- `commit_cb`: Transaction commit
- `message_cb`: Logical decoding messages
- `shutdown_cb`: Cleanup

---

## 3. Replication Slots

### 3.1 Purpose and Design

Replication slots provide persistence and feedback for replication connections. They solve two critical problems:

1. **WAL Retention**: Prevent WAL removal while standby is disconnected
2. **Position Tracking**: Remember replication position across reconnections

**Replication Slot Persistency** (`src/include/replication/slot.h:43-48`):

```c
typedef enum ReplicationSlotPersistency
{
    RS_PERSISTENT,      /* Crash-safe, survives restarts */
    RS_EPHEMERAL,       /* Temporary during slot creation */
    RS_TEMPORARY,       /* Session-scoped, dropped on disconnect */
} ReplicationSlotPersistency;
```

### 3.2 ReplicationSlot Data Structure

**Persistent Data** (`src/include/replication/slot.h:77-144`):

```c
typedef struct ReplicationSlotPersistentData
{
    /* The slot's identifier */
    NameData    name;

    /* database the slot is active on */
    Oid         database;

    /* The slot's behaviour when being dropped */
    ReplicationSlotPersistency persistency;

    /*
     * xmin horizon for data
     * NB: This may represent a value that hasn't been written to disk yet
     */
    TransactionId xmin;

    /*
     * xmin horizon for catalog tuples
     */
    TransactionId catalog_xmin;

    /* oldest LSN that might be required by this replication slot */
    XLogRecPtr  restart_lsn;

    /* RS_INVAL_NONE if valid, or the reason for invalidation */
    ReplicationSlotInvalidationCause invalidated;

    /*
     * Oldest LSN that the client has acked receipt for.
     */
    XLogRecPtr  confirmed_flush;

    /* LSN at which we enabled two_phase commit */
    XLogRecPtr  two_phase_at;

    /* Allow decoding of prepared transactions? */
    bool        two_phase;

    /* plugin name */
    NameData    plugin;

    /* Was this slot synchronized from the primary server? */
    bool        synced;

    /* Is this a failover slot (sync candidate for standbys)? */
    bool        failover;
} ReplicationSlotPersistentData;
```

**In-Memory Slot Structure** (`src/include/replication/slot.h:162-252`):

```c
typedef struct ReplicationSlot
{
    /* lock, on same cacheline as effective_xmin */
    slock_t     mutex;

    /* is this slot defined */
    bool        in_use;

    /* Who is streaming out changes for this slot? */
    pid_t       active_pid;

    /* any outstanding modifications? */
    bool        just_dirtied;
    bool        dirty;

    /*
     * For logical decoding, this represents the latest xmin that has
     * actually been written to disk. For streaming replication, it's
     * just the same as the persistent value.
     */
    TransactionId effective_xmin;
    TransactionId effective_catalog_xmin;

    /* data surviving shutdowns and crashes */
    ReplicationSlotPersistentData data;

    /* is somebody performing io on this slot? */
    LWLock      io_in_progress_lock;

    /* Condition variable signaled when active_pid changes */
    ConditionVariable active_cv;

    /* Logical slot specific fields */
    TransactionId candidate_catalog_xmin;
    XLogRecPtr  candidate_xmin_lsn;
    XLogRecPtr  candidate_restart_valid;
    XLogRecPtr  candidate_restart_lsn;

    /* Last confirmed_flush LSN flushed to disk */
    XLogRecPtr  last_saved_confirmed_flush;

    /* Time when the slot became inactive */
    TimestampTz inactive_since;

    /* Latest restart_lsn that has been flushed to disk */
    XLogRecPtr  last_saved_restart_lsn;
} ReplicationSlot;
```

### 3.3 Slot Invalidation

Replication slots can be invalidated for several reasons to prevent unbounded WAL accumulation:

**Invalidation Causes** (`src/include/replication/slot.h:58-69`):

```c
typedef enum ReplicationSlotInvalidationCause
{
    RS_INVAL_NONE = 0,
    /* required WAL has been removed */
    RS_INVAL_WAL_REMOVED = (1 << 0),
    /* required rows have been removed */
    RS_INVAL_HORIZON = (1 << 1),
    /* wal_level insufficient for slot */
    RS_INVAL_WAL_LEVEL = (1 << 2),
    /* idle slot timeout has occurred */
    RS_INVAL_IDLE_TIMEOUT = (1 << 3),
} ReplicationSlotInvalidationCause;
```

**Protection Mechanisms**:

- `max_slot_wal_keep_size`: Limit WAL retention per slot
- `wal_keep_size`: Global minimum WAL retention
- `idle_replication_slot_timeout`: Invalidate inactive slots
- Catalog xmin: Prevent vacuum from removing needed tuples

---

## 4. Hot Standby Implementation

### 4.1 Hot Standby Architecture

Hot Standby enables read-only queries on standby servers during WAL replay. This requires sophisticated conflict resolution between recovery and active queries.

**Key Components**:

1. **Startup Process**: Replays WAL records
2. **Standby Snapshot Manager**: Maintains consistent snapshots for queries
3. **Conflict Resolution**: Handles conflicts between recovery and queries
4. **Feedback Mechanism**: Informs primary about standby's snapshot requirements

### 4.2 WAL Replay During Hot Standby

The startup process replays WAL while managing concurrent queries:

**Recovery States** (`src/include/access/xlog.h:89-94`):

```c
typedef enum RecoveryState
{
    RECOVERY_STATE_CRASH = 0,   /* crash recovery */
    RECOVERY_STATE_ARCHIVE,     /* archive recovery */
    RECOVERY_STATE_DONE,        /* currently in production */
} RecoveryState;
```

**Conflict Types**:

1. **Snapshot Conflicts**: Recovery removes tuples still visible to standby queries
2. **Tablespace Conflicts**: Recovery drops tablespace with active connections
3. **Database Conflicts**: Recovery drops database with active connections
4. **Lock Conflicts**: Recovery acquires locks conflicting with query locks
5. **Buffer Pin Conflicts**: Recovery needs to modify pinned buffers
6. **Startup Deadlock**: Recovery blocked by query holding needed locks

### 4.3 Hot Standby Feedback

Standby servers can send feedback to the primary about their oldest running transaction, preventing the primary from removing tuples still needed by standby queries.

**Configuration**:
```sql
-- On standby
hot_standby_feedback = on
```

**Mechanism**:
1. Standby calculates its global xmin from all active snapshots
2. WalReceiver sends xmin in status messages to WalSender
3. Primary's GetOldestActiveTransactionId() considers standby xmin
4. Vacuum and HOT cleanup respect standby's visibility requirements

**Trade-offs**:
- **Benefit**: Prevents query cancellations on standby
- **Cost**: Primary bloat increases to accommodate standby queries
- **Recommendation**: Use for critical read workloads, monitor primary bloat

---

## 5. Point-In-Time Recovery (PITR)

### 5.1 PITR Overview

Point-In-Time Recovery allows restoring a database to any point in its WAL history, enabling recovery from logical errors (dropped tables, bad updates) rather than just hardware failures.

**Recovery Target Types** (`src/include/access/xlogrecovery.h:23-31`):

```c
typedef enum
{
    RECOVERY_TARGET_UNSET,      /* No specific target, recover to end of WAL */
    RECOVERY_TARGET_XID,        /* Recover to specific transaction ID */
    RECOVERY_TARGET_TIME,       /* Recover to specific timestamp */
    RECOVERY_TARGET_NAME,       /* Recover to named restore point */
    RECOVERY_TARGET_LSN,        /* Recover to specific LSN */
    RECOVERY_TARGET_IMMEDIATE,  /* Stop at consistency point */
} RecoveryTargetType;
```

**Recovery Target Actions** (`src/include/access/xlogrecovery.h:46-51`):

```c
typedef enum
{
    RECOVERY_TARGET_ACTION_PAUSE,       /* Pause at target */
    RECOVERY_TARGET_ACTION_PROMOTE,     /* Promote to primary at target */
    RECOVERY_TARGET_ACTION_SHUTDOWN,    /* Shutdown at target */
} RecoveryTargetAction;
```

### 5.2 PITR Configuration

**postgresql.conf settings**:

```ini
# Recovery target
recovery_target = 'immediate'                    # Or unset for full recovery
recovery_target_time = '2025-01-15 14:30:00'    # Timestamp target
recovery_target_xid = '12345678'                 # Transaction ID target
recovery_target_lsn = '0/3000000'               # LSN target
recovery_target_name = 'before_bad_update'       # Named restore point
recovery_target_inclusive = true                 # Include target transaction?

# Recovery behavior
recovery_target_action = 'promote'              # pause | promote | shutdown
recovery_target_timeline = 'latest'             # Timeline to recover

# WAL archive access
restore_command = 'cp /archive/%f %p'           # Command to fetch archived WAL
recovery_end_command = '/usr/local/bin/cleanup' # Run after recovery completes
```

### 5.3 Creating Restore Points

Applications can create named restore points for predictable recovery targets:

```sql
-- Create a named restore point
SELECT pg_create_restore_point('before_schema_migration');

-- In recovery, specify:
-- recovery_target_name = 'before_schema_migration'
```

### 5.4 Timeline Management

Every PITR recovery creates a new timeline, preventing accidental replay of WAL from the original timeline:

**Timeline Workflow**:

1. **Initial Timeline**: Database starts on timeline 1
2. **PITR Recovery**: Recovery to specific point creates timeline 2
3. **History File**: `00000002.history` records timeline branching
4. **New WAL**: Post-recovery WAL written to timeline 2 files
5. **Cascade Recovery**: Can recover from timeline 2 to create timeline 3

**Timeline History File Format**:
```
# Timeline history file for timeline 2
# Created by recovery ending at 2025-01-15 14:30:00
1       0/3000000       "Recovery from transaction ID 12345678"
```

---

## 6. Crash Recovery and Checkpoints

### 6.1 Crash Recovery Mechanism

Crash recovery restores database consistency after an unexpected shutdown by replaying WAL from the last checkpoint to the end of WAL.

**Recovery Workflow**:

1. **Locate Checkpoint**: Read `pg_control` to find last checkpoint location
2. **Read Checkpoint Record**: Parse checkpoint record from WAL
3. **Determine Redo Point**: Set recovery starting point (checkpoint's redo LSN)
4. **Replay WAL**: Apply all WAL records from redo point to end of valid WAL
5. **Consistency Point**: Mark database consistent when sufficient WAL replayed
6. **End Recovery**: Create new checkpoint and transition to normal operation

**StartupXLOG Entry Point** (`src/backend/access/transam/xlogrecovery.c`):

The startup process's main function coordinates the entire recovery sequence, handling checkpoint location, WAL reading, record application, and transition to normal operation.

### 6.2 Checkpoint Algorithm

Checkpoints are the foundation of crash recovery, establishing consistent on-disk states that limit WAL replay requirements.

**CreateCheckPoint Function** (`src/backend/access/transam/xlog.c:6961`):

The checkpoint algorithm proceeds in seven distinct phases:

**Phase 1: Preparation**
```
1. Determine if shutdown checkpoint (CHECKPOINT_IS_SHUTDOWN flag)
2. Validate not in recovery (except for CHECKPOINT_END_OF_RECOVERY)
3. Initialize checkpoint statistics structure
4. Call SyncPreCheckpoint() for storage manager preparation
```

**Phase 2: Determine REDO Point**
```
5. Enter critical section
6. If shutdown checkpoint:
   - Wait for all transactions to complete
   - Set redo point to current insert position
7. If online checkpoint:
   - Set redo point to last checkpoint's redo point or earlier
8. Collect list of virtual transaction IDs for waiting
```

**Phase 3: Update Shared Memory**
```
9. Update checkpoint record in memory:
   - redo: LSN to start recovery from
   - ThisTimeLineID: Current timeline
   - PrevTimeLineID: Previous timeline
   - fullPageWrites: Whether full page writes are enabled
   - nextXid: Next transaction ID to assign
   - nextOid: Next OID to assign
   - nextMulti: Next MultiXactId
   - oldestXid: Oldest transaction ID still visible
   - oldestActiveXid: Oldest transaction ID still running
```

**Phase 4: Write Checkpoint Record**
```
10. Construct checkpoint WAL record
11. XLogInsert() writes checkpoint record to WAL
12. Update pg_control with checkpoint location
13. XLogFlush() ensures checkpoint record is durable
```

**Phase 5: Buffer and SLRU Checkpoint**
```
14. Exit critical section
15. CheckPointGuts() flushes:
    - All dirty shared buffers to disk
    - CLOG (transaction status) buffers
    - SUBTRANS (subtransaction) buffers
    - MultiXact buffers
    - Other SLRU structures
16. Record buffer statistics (buffers written)
```

**Phase 6: Sync All Files**
```
17. CheckPointTwoPhase() - flush two-phase state files
18. CheckPointReplicationSlots() - save replication slot state
19. CheckPointSnapBuild() - save snapshot builder state
20. CheckPointLogicalRewriteHeap() - sync logical rewrite state
21. SyncPostCheckpoint() - fsync all pending file operations
```

**Phase 7: Cleanup and Statistics**
```
22. Remove old WAL files (RemoveOldXlogFiles):
    - Keep WAL required by replication slots
    - Keep WAL required by max_wal_size
    - Keep WAL required by wal_keep_size
23. Recycle WAL segments for future use
24. Update checkpoint statistics:
    - Checkpoint completion time
    - Number of buffers written
    - Number of segments added/removed/recycled
25. Log checkpoint completion if log_checkpoints=on
```

**Checkpoint Statistics** (`src/include/access/xlog.h:160-181`):

```c
typedef struct CheckpointStatsData
{
    TimestampTz ckpt_start_t;       /* start of checkpoint */
    TimestampTz ckpt_write_t;       /* start of flushing buffers */
    TimestampTz ckpt_sync_t;        /* start of fsyncs */
    TimestampTz ckpt_sync_end_t;    /* end of fsyncs */
    TimestampTz ckpt_end_t;         /* end of checkpoint */

    int         ckpt_bufs_written;  /* # of buffers written */
    int         ckpt_slru_written;  /* # of SLRU buffers written */

    int         ckpt_segs_added;    /* # of new xlog segments created */
    int         ckpt_segs_removed;  /* # of xlog segments deleted */
    int         ckpt_segs_recycled; /* # of xlog segments recycled */

    int         ckpt_sync_rels;     /* # of relations synced */
    uint64      ckpt_longest_sync;  /* Longest sync for one relation */
    uint64      ckpt_agg_sync_time; /* Sum of all individual sync times */
} CheckpointStatsData;
```

### 6.3 Checkpoint Scheduling

PostgreSQL uses multiple strategies to trigger checkpoints:

**Checkpoint Triggers**:

1. **Time-Based**: `checkpoint_timeout` (default: 5 minutes)
2. **WAL-Based**: `max_wal_size` exceeded (default: 1GB)
3. **Explicit**: `CHECKPOINT` SQL command
4. **Shutdown**: Server shutdown or restart
5. **Archive**: Before switching to new WAL segment if archiving

**Checkpoint Request Flags** (`src/include/access/xlog.h:139-150`):

```c
/* These directly affect the behavior of CreateCheckPoint */
#define CHECKPOINT_IS_SHUTDOWN      0x0001  /* Checkpoint is for shutdown */
#define CHECKPOINT_END_OF_RECOVERY  0x0002  /* End of WAL recovery */
#define CHECKPOINT_FAST             0x0004  /* Do it without delays */
#define CHECKPOINT_FORCE            0x0008  /* Force even if no activity */
#define CHECKPOINT_FLUSH_UNLOGGED   0x0010  /* Flush unlogged tables */

/* These are important to RequestCheckpoint */
#define CHECKPOINT_WAIT             0x0020  /* Wait for completion */
#define CHECKPOINT_REQUESTED        0x0040  /* Checkpoint request made */

/* These indicate the cause of a checkpoint request */
#define CHECKPOINT_CAUSE_XLOG       0x0080  /* XLOG consumption */
#define CHECKPOINT_CAUSE_TIME       0x0100  /* Elapsed time */
```

### 6.4 Checkpoint Tuning

Optimal checkpoint configuration balances recovery time against I/O impact:

**Key Parameters**:

```ini
# Checkpoint frequency
checkpoint_timeout = 15min          # Time-based checkpoint interval
max_wal_size = 4GB                  # WAL size trigger (soft limit)
min_wal_size = 1GB                  # Minimum WAL to keep

# Checkpoint spreading
checkpoint_completion_target = 0.9  # Spread checkpoint over 90% of interval

# WAL segment management
wal_keep_size = 1GB                 # WAL to keep for replication
max_slot_wal_keep_size = 10GB       # Per-slot WAL limit

# Logging
log_checkpoints = on                # Log checkpoint statistics
```

**Tuning Strategy**:

1. **For Fast Recovery**: Shorter `checkpoint_timeout`, smaller `max_wal_size`
   - Reduces WAL replay time
   - Increases checkpoint overhead

2. **For Performance**: Longer `checkpoint_timeout`, larger `max_wal_size`
   - Reduces checkpoint I/O impact
   - Increases recovery time

3. **For Smooth I/O**: `checkpoint_completion_target` near 0.9
   - Spreads checkpoint writes over time
   - Reduces I/O spikes

**Monitoring**:

```sql
-- Check checkpoint statistics
SELECT * FROM pg_stat_bgwriter;

-- Monitor checkpoint timing
SELECT
    checkpoint_lsn,
    redo_lsn,
    checkpoint_time,
    redo_wal_file
FROM pg_control_checkpoint();

-- View current WAL position
SELECT pg_current_wal_lsn();

-- Calculate WAL generation rate
SELECT
    (pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') /
     EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time()))) / 1024 / 1024
    AS mb_per_second;
```

---

## 7. pg_basebackup Integration

### 7.1 pg_basebackup Overview

`pg_basebackup` is PostgreSQL's built-in tool for creating base backups of running clusters. It integrates deeply with the replication infrastructure to produce consistent backups without blocking normal operations.

**Location**: `/home/user/postgres/src/bin/pg_basebackup/`

**Key Features**:
- Non-blocking online backup
- Streaming or archive-based WAL inclusion
- Progress reporting
- Compression support (gzip, lz4, zstd)
- Verification capabilities
- Direct tar or plain format output

### 7.2 Backup Protocol

`pg_basebackup` uses the replication protocol with backup-specific commands:

**Backup Workflow**:

1. **Connection**: Connect to primary with `replication=database` or `replication=true`
2. **Slot Creation** (optional): Create temporary or permanent replication slot
3. **Backup Start**: Issue `BASE_BACKUP` replication command
4. **Label Recording**: Server creates `backup_label` with start position
5. **File Transfer**: Receive base directory contents via COPY protocol
6. **Tablespace Transfer**: Receive each tablespace separately
7. **WAL Streaming**: Concurrently stream WAL to ensure consistency
8. **Backup End**: Receive `backup_label` and tablespace map
9. **Slot Cleanup**: Drop temporary slot if used

**BASE_BACKUP Command Syntax**:
```
BASE_BACKUP [ LABEL 'label' ]
            [ PROGRESS ]
            [ FAST ]
            [ WAL ]
            [ NOWAIT ]
            [ MAX_RATE rate ]
            [ TABLESPACE_MAP ]
            [ VERIFY_CHECKSUMS ]
```

### 7.3 WAL Streaming During Backup

To ensure backup consistency, all WAL generated during the backup must be captured:

**Method 1: Integrated WAL Streaming** (default with `-X stream`):
- Spawns parallel connection to stream WAL
- Stores WAL in backup's `pg_wal` directory
- Backup is self-contained and immediately usable

**Method 2: Fetch After Backup** (with `-X fetch`):
- Waits for WAL archiving after backup completes
- Retrieves archived WAL segments
- Requires functional WAL archiving

**Method 3: Manual WAL Management** (with `-X none`):
- Relies on separate WAL archiving
- Restore requires `restore_command` configuration
- Smallest backup size (no WAL included)

### 7.4 Backup Label and Tablespace Map

**backup_label File**:
```
START WAL LOCATION: 0/3000028 (file 000000010000000000000003)
CHECKPOINT LOCATION: 0/3000060
BACKUP METHOD: streamed
BACKUP FROM: primary
START TIME: 2025-01-15 14:30:00 UTC
LABEL: Weekly backup
START TIMELINE: 1
```

The `backup_label` file is critical for recovery - it tells the startup process:
- Where to begin WAL replay (START WAL LOCATION)
- Not to use normal checkpoint-based recovery
- What backup method was used

**tablespace_map File**:
```
16384 /var/lib/pgsql/tablespaces/fast_ssd
16385 /var/lib/pgsql/tablespaces/archive_disk
```

Maps tablespace OIDs to their locations, enabling restore to different paths.

### 7.5 Replication Slot Integration

Using replication slots with pg_basebackup prevents WAL removal during long backups:

```bash
# Create backup with permanent slot
pg_basebackup -D /backup -X stream -S backup_slot -C

# Use existing slot
pg_basebackup -D /backup -X stream -S existing_slot

# Create temporary slot (auto-dropped after backup)
pg_basebackup -D /backup -X stream -C --slot temp_backup_slot
```

**Benefits**:
- Guarantees WAL availability during backup
- Essential for slow backups or network interruptions
- Enables backup verification without time pressure

**Risks**:
- Unused slots prevent WAL recycling
- Can cause disk space exhaustion on primary
- Must monitor and drop abandoned slots

### 7.6 Backup Verification

PostgreSQL 13+ includes backup manifest verification:

```bash
# Create backup with manifest
pg_basebackup -D /backup --manifest-checksums=SHA256

# Verify backup integrity
pg_verifybackup /backup
```

**Manifest Contents**:
- File list with sizes and modification times
- Checksums (CRC32C, SHA224, SHA256, SHA384, SHA512)
- WAL range required for recovery
- Backup timeline

---

## 8. Advanced Replication Topics

### 8.1 Synchronous Replication

Synchronous replication provides zero data loss by waiting for standby confirmation before commit:

**Configuration**:
```ini
# On primary
synchronous_standby_names = 'FIRST 2 (standby1, standby2, standby3)'
synchronous_commit = on  # Per session or globally
```

**Synchronous Commit Levels**:
- `off`: No wait for WAL write (fastest, data loss risk)
- `local`: Wait for local WAL flush only
- `remote_write`: Wait for standby WAL write (not flush)
- `remote_apply`: Wait for standby WAL application (no read lag)
- `on`: Wait for standby WAL flush (default synchronous)

**Quorum Commit**:
```ini
# Wait for ANY 2 of 4 standbys
synchronous_standby_names = 'ANY 2 (s1, s2, s3, s4)'

# Wait for FIRST 1 (prioritized)
synchronous_standby_names = 'FIRST 1 (s1, s2, s3)'
```

### 8.2 Cascading Replication

Standbys can serve as primary for downstream standbys, creating replication hierarchies:

**Architecture**:
```
Primary → Standby A → Standby A1
               ↓
          Standby A2
```

**Configuration on Standby A**:
```ini
# Enable accepting replication connections
hot_standby = on
max_wal_senders = 5
```

**Benefits**:
- Reduces primary load
- Geographic distribution
- Network efficiency (local cascading)

**Considerations**:
- Increased replication lag down the chain
- Middle node failure impacts downstream
- Monitoring complexity

### 8.3 Delayed Replication

Intentional replication delay protects against logical errors:

```ini
# On standby
recovery_min_apply_delay = '4h'
```

**Use Case**: Protection against accidental data corruption or deletion
- Corrupted data replicates to standby after 4 hours
- Within delay window, can promote delayed standby with uncorrupted data
- Acts as "time machine" for disaster recovery

### 8.4 Bi-Directional Replication

Logical replication enables bidirectional replication for multi-master scenarios:

**Setup**:

```sql
-- On node1
CREATE PUBLICATION node1_pub FOR ALL TABLES;

-- On node2
CREATE PUBLICATION node2_pub FOR ALL TABLES;
CREATE SUBSCRIPTION node2_sub
    CONNECTION 'host=node1 dbname=mydb'
    PUBLICATION node1_pub
    WITH (origin = none);  -- Prevent replication loops

-- On node1
CREATE SUBSCRIPTION node1_sub
    CONNECTION 'host=node2 dbname=mydb'
    PUBLICATION node2_pub
    WITH (origin = none);
```

**Conflict Resolution**:
- PostgreSQL uses "last update wins" by commit timestamp
- No automatic conflict detection - application must ensure
- Consider using `origin` parameter to track data source

---

## 9. Monitoring and Diagnostics

### 9.1 Replication Monitoring Views

**pg_stat_replication**: WalSender status from primary

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;
```

**pg_stat_wal_receiver**: WalReceiver status on standby

```sql
SELECT
    status,
    receive_start_lsn,
    receive_start_tli,
    written_lsn,
    flushed_lsn,
    received_tli,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_lsn,
    latest_end_time
FROM pg_stat_wal_receiver;
```

**pg_replication_slots**: Replication slot status

```sql
SELECT
    slot_name,
    plugin,
    slot_type,
    database,
    active,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size
FROM pg_replication_slots;
```

### 9.2 Lag Monitoring

**Byte Lag on Primary**:

```sql
SELECT
    application_name,
    client_addr,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS byte_lag,
    replay_lag
FROM pg_stat_replication;
```

**Replay Position on Standby**:

```sql
SELECT
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn,
    pg_wal_lsn_diff(
        pg_last_wal_receive_lsn(),
        pg_last_wal_replay_lsn()
    ) AS replay_lag_bytes;
```

**Time-Based Lag**:

```sql
SELECT
    now() - pg_last_xact_replay_timestamp() AS replication_lag_time;
```

### 9.3 WAL Generation Monitoring

```sql
-- Current WAL insert position
SELECT pg_current_wal_lsn();

-- WAL generation rate
SELECT
    (pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') /
     EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time())))
    AS wal_bytes_per_second;

-- Checkpoint statistics
SELECT * FROM pg_stat_bgwriter;

-- WAL archiving status
SELECT * FROM pg_stat_archiver;
```

### 9.4 Diagnostic Queries

**Check if in recovery**:
```sql
SELECT pg_is_in_recovery();
```

**Current recovery timeline**:
```sql
SELECT timeline_id, redo_lsn FROM pg_control_checkpoint();
```

**Oldest replication slot holding WAL**:
```sql
SELECT
    slot_name,
    restart_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes
FROM pg_replication_slots
WHERE restart_lsn IS NOT NULL
ORDER BY restart_lsn
LIMIT 1;
```

**Replication slot disk usage**:
```sql
SELECT
    slot_name,
    wal_status,
    safe_wal_size / 1024 / 1024 AS safe_wal_mb
FROM pg_replication_slots;
```

---

## 10. Common Replication Patterns

### 10.1 Primary-Standby (Active-Passive)

**Purpose**: High availability with automatic failover

**Setup**:
```ini
# Primary
wal_level = replica
max_wal_senders = 5
wal_keep_size = 1024

# Standby
primary_conninfo = 'host=primary port=5432 user=replication'
primary_slot_name = 'standby1_slot'
hot_standby = on
```

**Failover Process**:
1. Verify primary is down
2. On standby: `pg_ctl promote` or create `promote` signal file
3. Reconfigure application to new primary
4. (Optional) Rebuild old primary as new standby

### 10.2 Primary with Multiple Standbys

**Purpose**: Load balancing read queries, geographic distribution

**Setup**:
```ini
# Primary
max_wal_senders = 10
synchronous_standby_names = 'FIRST 1 (standby_local, standby_remote)'

# Standby configs differ only in:
primary_slot_name = 'standby1_slot'  # Unique per standby
```

### 10.3 Logical Replication for Upgrades

**Purpose**: Zero-downtime major version upgrade

**Workflow**:
1. Set up new version cluster
2. Create publication on old version
3. Create subscription on new version
4. Wait for sync completion
5. Switch applications to new version
6. Decommission old version

**Setup**:
```sql
-- On old cluster (e.g., PG 14)
CREATE PUBLICATION upgrade_pub FOR ALL TABLES;

-- On new cluster (e.g., PG 16)
CREATE SUBSCRIPTION upgrade_sub
    CONNECTION 'host=old_cluster port=5432 dbname=mydb'
    PUBLICATION upgrade_pub;

-- Monitor sync status
SELECT * FROM pg_subscription;
SELECT * FROM pg_stat_subscription;
```

### 10.4 Multi-Region Active-Active

**Purpose**: Local writes with global consistency

**Architecture**: Logical replication between regions with application-level conflict avoidance

**Setup Principle**:
```sql
-- Region A handles customers A-M
-- Region B handles customers N-Z
-- Each region publishes its partition
-- Each region subscribes to other region's publication
-- Application routes writes to owning region
```

---

## 11. Troubleshooting

### 11.1 Replication Lag Investigation

**Symptom**: Standby falls behind primary

**Diagnostic Steps**:

```sql
-- 1. Check lag metrics
SELECT * FROM pg_stat_replication;

-- 2. Check for long-running transactions on primary
SELECT pid, now() - xact_start AS duration, state, query
FROM pg_stat_activity
WHERE state = 'active' AND xact_start < now() - interval '1 hour';

-- 3. Check for hot standby conflicts
SELECT * FROM pg_stat_database_conflicts;

-- 4. Check WAL generation rate
SELECT
    (pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') /
     EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time()))) / 1024 / 1024
    AS mb_per_second;

-- 5. Check standby system resources (CPU, IO, network)
-- Use OS tools: iostat, vmstat, iftop
```

**Common Causes**:
- Network bandwidth saturation
- Standby I/O bottleneck (slow storage)
- Large transactions on primary
- Hot standby conflicts
- Standby resource exhaustion

### 11.2 Replication Slot Issues

**Symptom**: Disk space exhaustion from WAL accumulation

**Diagnostic**:

```sql
-- Check slot WAL retention
SELECT
    slot_name,
    active,
    wal_status,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / 1024 / 1024 AS mb_behind
FROM pg_replication_slots
ORDER BY restart_lsn;
```

**Resolution**:

```sql
-- 1. Identify problematic slot
-- (Inactive slot with large mb_behind)

-- 2. If slot is truly abandoned, drop it:
SELECT pg_drop_replication_slot('abandoned_slot');

-- 3. If slot is for valid standby that's disconnected:
--    - Fix standby connectivity
--    - If catch-up impossible, rebuild standby with pg_basebackup
--    - Then recreate/reuse slot
```

### 11.3 Hot Standby Query Conflicts

**Symptom**: Queries on standby canceled with "conflict with recovery"

**Check conflict statistics**:

```sql
SELECT * FROM pg_stat_database_conflicts;
```

**Resolution Options**:

1. **Enable hot_standby_feedback**:
```ini
# On standby
hot_standby_feedback = on
```
Pro: Prevents conflicts
Con: Primary bloat

2. **Increase max_standby_streaming_delay**:
```ini
# On standby
max_standby_streaming_delay = 600s  # Default: 30s
```
Pro: Gives queries more time
Con: Increases replication lag

3. **Use delayed standby for reporting**:
```ini
recovery_min_apply_delay = '1h'
```
Pro: Conflict-free reporting
Con: Stale data

### 11.4 Logical Replication Issues

**Symptom**: Subscription falls behind or fails

**Diagnostic**:

```sql
-- Check subscription status
SELECT * FROM pg_stat_subscription;

-- Check replication slot on publisher
SELECT * FROM pg_replication_slots WHERE slot_name = 'subscription_slot';

-- Check for errors in subscriber logs
-- Look for: constraint violations, schema mismatches, permission errors
```

**Common Issues**:

1. **Schema Mismatch**: Subscriber table definition differs from publisher
   - Solution: Ensure compatible schemas, use `ALTER SUBSCRIPTION REFRESH PUBLICATION`

2. **Constraint Violations**: Unique constraint on subscriber violated by replicated data
   - Solution: Fix data on subscriber, or disable constraint during initial sync

3. **Permission Errors**: Subscription user lacks necessary privileges
   - Solution: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user`

---

## 12. Performance Optimization

### 12.1 WAL Configuration Tuning

```ini
# Increase WAL buffers for high-write workloads
wal_buffers = 16MB                  # Default: -1 (auto)

# Batch WAL writes for better throughput
commit_delay = 10                   # microseconds to delay commit
commit_siblings = 5                 # require this many concurrent commits

# Disable full page writes if on crash-safe storage (carefully!)
full_page_writes = on               # Usually keep enabled

# Enable WAL compression for network-bound replication
wal_compression = lz4               # none | pglz | lz4 | zstd
```

### 12.2 Replication Performance

```ini
# Increase max_wal_senders for many standbys
max_wal_senders = 10                # Usually 2x number of standbys

# Increase wal_sender_timeout to handle slow networks
wal_sender_timeout = 60s            # Default: 60s

# On standby, increase apply performance
max_parallel_maintenance_workers = 4
max_parallel_workers = 8
```

### 12.3 Checkpoint Tuning for Replication

```ini
# Larger checkpoints reduce frequency, improve throughput
max_wal_size = 8GB                  # Soft limit
checkpoint_timeout = 30min          # Time-based trigger

# Spread checkpoint I/O
checkpoint_completion_target = 0.9  # Spread over 90% of timeout

# Monitor checkpoint performance
log_checkpoints = on
```

---

## 13. Security Considerations

### 13.1 Replication Authentication

**pg_hba.conf Configuration**:

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Allow replication from trusted standby
host    replication     replicator      192.168.1.10/32         scram-sha-256

# Require SSL for remote replication
hostssl replication     replicator      10.0.0.0/8              scram-sha-256

# Local replication for backup
local   replication     backup_user                             peer
```

**Create Replication User**:

```sql
CREATE ROLE replicator WITH
    LOGIN
    REPLICATION
    PASSWORD 'secure_password';
```

### 13.2 SSL/TLS for Replication

**On Primary**:

```ini
ssl = on
ssl_cert_file = '/etc/ssl/certs/server.crt'
ssl_key_file = '/etc/ssl/private/server.key'
ssl_ca_file = '/etc/ssl/certs/ca.crt'
```

**On Standby**:

```ini
primary_conninfo = 'host=primary port=5432 user=replicator sslmode=verify-full sslrootcert=/etc/ssl/certs/ca.crt'
```

**SSL Modes**:
- `disable`: No SSL
- `allow`: Try SSL, fall back to unencrypted
- `prefer`: Prefer SSL, fall back to unencrypted
- `require`: Require SSL, any certificate
- `verify-ca`: Require SSL, verify CA
- `verify-full`: Require SSL, verify CA and hostname

---

## 14. Future Directions

### 14.1 Ongoing Developments

**Logical Replication Enhancements**:
- DDL replication support
- Sequence replication improvements
- Conflict detection and resolution
- Bi-directional replication improvements

**Physical Replication Features**:
- Faster catchup algorithms
- Improved synchronous replication performance
- Better compression algorithms

**Backup and Recovery**:
- Incremental backup support
- Faster backup and restore
- Built-in backup verification
- Block-level incremental backups

### 14.2 PostgreSQL 17+ Features

Recent PostgreSQL versions introduced:
- **Logical replication of sequences**: Replicate sequence state
- **Failover slots**: Automatic slot creation on promoted standby
- **Improved streaming large transactions**: Better memory management
- **Enhanced pg_basebackup**: Better progress reporting, verification

---

## 15. Summary

PostgreSQL's replication and recovery systems provide comprehensive solutions for high availability, disaster recovery, and data protection:

**Streaming Replication**:
- WAL-based physical replication with minimal lag
- WalSender/WalReceiver architecture for efficient streaming
- Synchronous and asynchronous modes for different guarantees

**Logical Replication**:
- Table-level selective replication
- Cross-version compatibility
- LogicalDecodingContext and ReorderBuffer for transaction reassembly

**Replication Slots**:
- Persistent replication position tracking
- WAL retention guarantees
- Protection mechanisms against unbounded growth

**Hot Standby**:
- Read-only queries during recovery
- Conflict resolution between recovery and queries
- Feedback mechanisms to reduce conflicts

**Recovery Mechanisms**:
- Crash recovery from last checkpoint
- Point-In-Time Recovery to specific targets
- Seven-phase checkpoint algorithm
- Timeline management for recovery branches

**pg_basebackup**:
- Online backup without blocking
- Integrated WAL streaming
- Replication slot integration
- Backup verification capabilities

These systems work together to provide robust, flexible replication and recovery capabilities suitable for applications ranging from small single-server deployments to large distributed systems with complex topologies and stringent availability requirements.

---

## References

**Source Code Locations**:
- `/home/user/postgres/src/include/replication/` - Replication headers
- `/home/user/postgres/src/backend/replication/` - Replication implementation
- `/home/user/postgres/src/backend/access/transam/xlog.c` - WAL and checkpoint code
- `/home/user/postgres/src/backend/access/transam/xlogrecovery.c` - Recovery implementation
- `/home/user/postgres/src/bin/pg_basebackup/` - Backup tools

**Key Data Structures**:
- `WalSnd` (`src/include/replication/walsender_private.h:41`)
- `WalRcvData` (`src/include/replication/walreceiver.h:57`)
- `ReplicationSlot` (`src/include/replication/slot.h:162`)
- `LogicalDecodingContext` (`src/include/replication/logical.h:33`)
- `ReorderBuffer` (`src/include/replication/reorderbuffer.h`)

**Related Chapters**:
- Chapter 1: WAL (Write-Ahead Log) Architecture
- Chapter 2: Storage Management
- Chapter 3: Transaction System
- Chapter 5: Query Processing

---

*PostgreSQL Encyclopedia - Chapter 4: Replication and Recovery Systems*
*Edition: PostgreSQL 17 Development (2025)*
