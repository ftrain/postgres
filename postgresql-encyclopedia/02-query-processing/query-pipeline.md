# PostgreSQL Query Processing Pipeline

## Table of Contents

1. [Introduction](#1-introduction)
2. [The Parser](#2-the-parser)
3. [The Rewriter](#3-the-rewriter)
4. [The Planner/Optimizer](#4-the-planneroptimizer)
5. [The Executor](#5-the-executor)
6. [Catalog System and Syscache](#6-catalog-system-and-syscache)
7. [Node Types and Data Structures](#7-node-types-and-data-structures)
8. [Join Algorithms](#8-join-algorithms)
9. [Cost Model and Parameters](#9-cost-model-and-parameters)
10. [Expression Evaluation](#10-expression-evaluation)
11. [Complete Query Example Walkthrough](#11-complete-query-example-walkthrough)

---

## 1. Introduction

PostgreSQL's query processing system transforms SQL statements into executable plans through a sophisticated four-stage pipeline: **parsing**, **rewriting**, **planning/optimization**, and **execution**. This architecture represents decades of evolution in database query processing, combining academic research with practical engineering to deliver both correctness and performance.

### 1.1 Query Processing Overview

```
SQL Text
    ↓
┌─────────────────┐
│  1. PARSER      │  Lexical/syntactic analysis, semantic transformation
│  gram.y (17,896 lines)        │
│  scan.l         │  → Parse Tree (RawStmt) → Query Tree
│  analyze.c      │
└─────────────────┘
    ↓
┌─────────────────┐
│  2. REWRITER    │  View expansion, rule application, RLS
│  rewriteHandler.c (3,877 lines)           │
└─────────────────┘  → Rewritten Query Tree(s)
    ↓
┌─────────────────┐
│  3. PLANNER     │  Path generation, cost estimation, plan selection
│  planner.c (7,341 lines)      │
│  Cost estimation│  → PlannedStmt (Plan Tree)
└─────────────────┘
    ↓
┌─────────────────┐
│  4. EXECUTOR    │  Plan execution, tuple generation
│  execMain.c (2,833 lines)     │
└─────────────────┘  → Result Tuples
```

### 1.2 Key Design Principles

**Separation of Concerns**: Each stage has a well-defined responsibility and produces specific output structures for the next stage.

**Extensibility**: Hook functions at each stage allow extensions to modify behavior without changing core code.

**Node-based Architecture**: All data structures are node types with uniform handling for copying, serialization, and debugging.

**Cost-based Optimization**: The planner evaluates multiple execution strategies and selects the plan with the lowest estimated cost.

---

## 2. The Parser

The parser transforms raw SQL text into a structured Query tree through lexical analysis, syntactic parsing, and semantic analysis.

### 2.1 Parser Components

#### Lexer (scan.l)

**Location**: `/home/user/postgres/src/backend/parser/scan.l`

The lexer performs tokenization, converting raw SQL text into a stream of tokens. Written using Flex (a lexical analyzer generator), it handles:

- **Keywords**: SELECT, FROM, WHERE, etc.
- **Identifiers**: Table names, column names (with case-folding)
- **Literals**: Strings, numbers, bit strings
- **Operators**: =, <, >, ||, etc.
- **Special characters**: Parentheses, commas, semicolons

```c
/* Example token definitions from scan.l */

{self}              { return yytext[0]; }
{operator}          { return process_operator(yytext); }
{integer}           { return process_integer_literal(yytext); }
{identifier}        { return process_identifier(yytext); }

/* String literal handling */
{quote}             {
    BEGIN(xq);
    startlit();
}
```

#### Grammar (gram.y)

**Location**: `/home/user/postgres/src/backend/parser/gram.y` (17,896 lines)

The grammar file defines SQL syntax using Bison (YACC-compatible parser generator). It contains production rules for every SQL construct PostgreSQL supports.

**Key Statistics**:
- **17,896 lines** of grammar rules
- Hundreds of non-terminals
- Complete SQL:2016 standard coverage plus PostgreSQL extensions

**Sample Production Rules**:

```yacc
/* Simple SELECT statement structure */
SelectStmt:
    select_no_parens            %prec UMINUS
    | select_with_parens        %prec UMINUS
    ;

select_no_parens:
    simple_select
    | select_clause sort_clause
    | select_clause opt_sort_clause for_locking_clause opt_select_limit
    | select_clause opt_sort_clause select_limit opt_for_locking_clause
    | with_clause select_clause
    ;

simple_select:
    SELECT opt_all_clause opt_target_list
        into_clause from_clause where_clause
        group_clause having_clause window_clause
        {
            SelectStmt *n = makeNode(SelectStmt);
            n->targetList = $3;
            n->intoClause = $4;
            n->fromClause = $5;
            n->whereClause = $6;
            n->groupClause = $7;
            n->havingClause = $8;
            n->windowClause = $9;
            $$ = (Node *) n;
        }
    ;

/* JOIN syntax */
joined_table:
    '(' joined_table ')'
    | table_ref CROSS JOIN table_ref
    | table_ref join_type JOIN table_ref join_qual
    | table_ref JOIN table_ref join_qual
    | table_ref NATURAL join_type JOIN table_ref
    ;

join_type:
    FULL join_outer             { $$ = JOIN_FULL; }
    | LEFT join_outer           { $$ = JOIN_LEFT; }
    | RIGHT join_outer          { $$ = JOIN_RIGHT; }
    | INNER_P                   { $$ = JOIN_INNER; }
    ;
```

#### Semantic Analysis (analyze.c)

**Location**: `/home/user/postgres/src/backend/parser/analyze.c`

The analyzer transforms the raw parse tree into a Query structure, performing:

1. **Name Resolution**: Resolving table/column references
2. **Type Checking**: Ensuring type compatibility
3. **Function Resolution**: Finding matching function signatures
4. **Subquery Processing**: Handling nested queries
5. **Aggregate Validation**: Checking aggregate usage rules
6. **Constraint Checking**: Validating NOT NULL, CHECK constraints

**Main Entry Point** (`lines 114-145`):

```c
/*
 * parse_analyze_fixedparams
 *		Analyze a raw parse tree and transform it to Query form.
 *
 * Optionally, information about $n parameter types can be supplied.
 * References to $n indexes not defined by paramTypes[] are disallowed.
 *
 * The result is a Query node.  Optimizable statements require considerable
 * transformation, while utility-type statements are simply hung off
 * a dummy CMD_UTILITY Query node.
 */
Query *
parse_analyze_fixedparams(RawStmt *parseTree, const char *sourceText,
                          const Oid *paramTypes, int numParams,
                          QueryEnvironment *queryEnv)
{
    ParseState *pstate = make_parsestate(NULL);
    Query      *query;
    JumbleState *jstate = NULL;

    Assert(sourceText != NULL); /* required as of 8.4 */

    pstate->p_sourcetext = sourceText;

    if (numParams > 0)
        setup_parse_fixed_parameters(pstate, paramTypes, numParams);

    pstate->p_queryEnv = queryEnv;

    query = transformTopLevelStmt(pstate, parseTree);

    if (IsQueryIdEnabled())
        jstate = JumbleQuery(query);

    if (post_parse_analyze_hook)
        (*post_parse_analyze_hook) (pstate, query, jstate);

    free_parsestate(pstate);

    pgstat_report_query_id(query->queryId, false);

    return query;
}
```

### 2.2 Parse Tree to Query Transformation

The transformation process converts syntactic structures into semantic ones:

**Example: Simple SELECT**

```sql
SELECT name, salary FROM employees WHERE dept_id = 10;
```

**RawStmt (Parse Tree)**:
```
SelectStmt {
    targetList: [
        ResTarget { name: "name" },
        ResTarget { name: "salary" }
    ],
    fromClause: [
        RangeVar { relname: "employees" }
    ],
    whereClause: A_Expr {
        kind: AEXPR_OP,
        name: "=",
        lexpr: ColumnRef { fields: ["dept_id"] },
        rexpr: A_Const { val: 10 }
    }
}
```

**Query (Semantic Tree)**:
```
Query {
    commandType: CMD_SELECT,
    rtable: [
        RangeTblEntry {
            rtekind: RTE_RELATION,
            relid: <OID of employees>,
            relkind: RELKIND_RELATION,
            requiredPerms: ACL_SELECT
        }
    ],
    targetList: [
        TargetEntry {
            expr: Var { varno: 1, varattno: 1, vartype: TEXT },
            resname: "name"
        },
        TargetEntry {
            expr: Var { varno: 1, varattno: 2, vartype: NUMERIC },
            resname: "salary"
        }
    ],
    jointree: FromExpr {
        quals: OpExpr {
            opno: <OID of int4eq>,
            args: [
                Var { varno: 1, varattno: 3, vartype: INT4 },
                Const { consttype: INT4, constvalue: 10 }
            ]
        }
    }
}
```

### 2.3 Parser Subsystems

#### Type Resolution

**Location**: `/home/user/postgres/src/backend/parser/parse_type.c`

Resolves type names to OIDs and validates type usage:

```c
/* Find a type by name */
Type
LookupTypeName(ParseState *pstate, const TypeName *typeName,
               int32 *typmod_p, bool missing_ok);

/* Verify types are compatible */
void
check_can_coerce(Oid inputTypeId, Oid targetTypeId);
```

#### Function Resolution

**Location**: `/home/user/postgres/src/backend/parser/parse_func.c`

Handles function name resolution with overloading:

```c
/*
 * func_select_candidate
 *   Given the input argtype array, attempt to select the best candidate
 *   function from the given list.
 *
 * Returns the index of the best candidate (0..ncandidates-1), or -1
 * if no candidate can be selected.
 */
static int
func_select_candidate(int nargs,
                     Oid *input_typeids,
                     FuncCandidateList candidates);
```

#### Aggregate Checking

**Location**: `/home/user/postgres/src/backend/parser/parse_agg.c`

Validates aggregate function usage:

```c
/*
 * parseCheckAggregates
 *   Check for aggregates where they shouldn't be and improper grouping.
 *
 * This is a fairly complex operation because of the various special cases
 * and because we must check the entire Query tree recursively.
 */
void
parseCheckAggregates(ParseState *pstate, Query *qry);
```

---

## 3. The Rewriter

The rewriter transforms Query trees by applying views, rules, and row-level security policies. This stage can transform a single query into multiple queries.

### 3.1 Rewriter Responsibilities

**Location**: `/home/user/postgres/src/backend/rewrite/rewriteHandler.c` (3,877 lines)

1. **View Expansion**: Replace view references with underlying queries
2. **Rule Application**: Execute query rewrite rules
3. **Row-Level Security**: Apply RLS policies
4. **Updatable View Handling**: Transform view updates into base table updates
5. **Inheritance Expansion**: Expand inherited table references

### 3.2 Main Rewrite Entry Point

```c
/*
 * QueryRewrite -
 *    Primary entry point to the query rewriter.
 *    Rewrite one query via query rewrite system, possibly returning 0
 *    or multiple queries.
 *
 * NOTE: The code in QueryRewrite was formerly in pg_parse_and_rewrite(),
 * and was split out to be called from plancache.c during plan invalidation.
 */
List *
QueryRewrite(Query *parsetree)
{
    uint64      input_query_id = parsetree->queryId;
    List       *querylist;
    List       *results;
    ListCell   *l;
    CmdType     orig_cmd = parsetree->commandType;
    bool        foundOriginalQuery = false;
    Query      *lastInstead = NULL;

    /*
     * This function is only applied to top-level original queries
     */
    Assert(parsetree->querySource == QSRC_ORIGINAL);
    Assert(parsetree->canSetTag);

    /*
     * Step 1
     *
     * Apply all non-SELECT rules possibly getting 0 or many queries
     */
    querylist = RewriteQuery(parsetree, NIL, 0);

    /* ... additional processing ... */

    return results;
}
```

### 3.3 View Expansion

When a query references a view, the rewriter replaces it with the view's defining query.

**Example**:

```sql
-- View definition
CREATE VIEW high_earners AS
    SELECT name, salary FROM employees WHERE salary > 100000;

-- Query
SELECT * FROM high_earners WHERE dept_id = 10;
```

**After Rewriting**:

```sql
SELECT name, salary
FROM employees
WHERE salary > 100000 AND dept_id = 10;
```

**Implementation** (fireRIRrules function):

```c
/*
 * fireRIRrules -
 *    Apply all Retrieve-Instead-Retrieve rules to the given querytree.
 *
 * This handles view expansion, including security barrier views.
 */
static Query *
fireRIRrules(Query *parsetree, List *activeRIRs)
{
    int         origResultRelation = parsetree->resultRelation;
    int         rt_index;
    ListCell   *lc;

    /*
     * Process each RTE (Range Table Entry) in the query.
     * For each RTE that references a relation, check if there's an
     * ON SELECT rule that needs to be applied.
     */
    rt_index = 0;
    foreach(lc, parsetree->rtable)
    {
        RangeTblEntry *rte = (RangeTblEntry *) lfirst(lc);
        Relation    rel;
        List       *locks;
        RuleLock   *rules;
        RewriteRule *rule;
        int         i;

        ++rt_index;

        if (rte->rtekind != RTE_RELATION)
            continue;

        /* Get the relation and its rules */
        rel = table_open(rte->relid, NoLock);
        rules = rel->rd_rules;

        /* ... apply ON SELECT rules ... */

        table_close(rel, NoLock);
    }

    return parsetree;
}
```

### 3.4 Row-Level Security (RLS)

**Location**: `/home/user/postgres/src/backend/rewrite/rowsecurity.c`

RLS adds additional WHERE clauses to enforce security policies:

```c
/*
 * prepend_row_security_policies -
 *    For a given query, add the row-level security quals
 *
 * New security barrier quals are added to the start of the relation's
 * baserestrictinfo list. We want them to be evaluated first, before any
 * user-supplied quals.
 */
void
prepend_row_security_policies(Query *root, RangeTblEntry *rte,
                              int rt_index)
{
    Relation    rel;
    List       *rowsec_policies;
    List       *rowsec_exprs;
    ListCell   *lc;

    /* ... RLS policy application ... */
}
```

**Example**:

```sql
-- Policy definition
CREATE POLICY employee_policy ON employees
    USING (dept_id = current_user_dept_id());

-- User query
SELECT * FROM employees;

-- After RLS rewriting
SELECT * FROM employees
WHERE dept_id = current_user_dept_id();
```

### 3.5 Updatable Views

The rewriter can transform INSERT/UPDATE/DELETE operations on views into operations on base tables:

```c
/*
 * rewriteTargetListIU -
 *    Rewrite the target list for INSERT and UPDATE queries
 *
 * This handles the translation from the view's columns to the
 * underlying table's columns.
 */
static List *
rewriteTargetListIU(List *targetList,
                   CmdType commandType,
                   OverridingKind override,
                   Relation target_relation,
                   RangeTblEntry *values_rte,
                   int values_rte_index,
                   Bitmapset **unused_values_attrnos)
{
    /* Transform view column references to base table references */
    /* Handle DEFAULT values, column ordering, etc. */
}
```

---

## 4. The Planner/Optimizer

The planner takes a Query tree and produces an optimal execution plan (PlannedStmt). This is the most complex component of the query processing pipeline.

### 4.1 Planner Architecture

**Location**: `/home/user/postgres/src/backend/optimizer/plan/planner.c` (7,341 lines)

The planner operates in several phases:

```
Query Tree
    ↓
┌──────────────────────────┐
│  Preprocessing           │  • Simplify expressions
│                          │  • Pull up subqueries
│                          │  • Flatten JOIN trees
└──────────────────────────┘  • Detect equivalence classes
    ↓
┌──────────────────────────┐
│  Path Generation         │  • Sequential scans
│                          │  • Index scans
│                          │  • Join methods
│                          │  • Parallel plans
└──────────────────────────┘
    ↓
┌──────────────────────────┐
│  Cost Estimation         │  • I/O costs
│                          │  • CPU costs
│                          │  • Selectivity estimation
└──────────────────────────┘
    ↓
┌──────────────────────────┐
│  Plan Selection          │  • Choose cheapest path
│                          │  • Create Plan nodes
└──────────────────────────┘
    ↓
PlannedStmt
```

### 4.2 Main Planner Entry Point

```c
/*
 * planner
 *   Main entry point for query optimizer.
 *
 * This function generates an execution plan for a Query.
 * The actual work is handed off to subquery_planner, which may recurse
 * for subqueries.
 */
PlannedStmt *
planner(Query *parse, const char *query_string, int cursorOptions,
        ParamListInfo boundParams)
{
    PlannedStmt *result;
    PlannerGlobal *glob;
    double      tuple_fraction;
    PlannerInfo *root;
    RelOptInfo *final_rel;
    Path       *best_path;
    Plan       *top_plan;
    ListCell   *lp,
               *lr;

    /*
     * Set up global state for this planner invocation.  This includes
     * information about available parameter values and the global
     * list of subqueries.
     */
    glob = makeNode(PlannerGlobal);
    glob->boundParams = boundParams;
    glob->subplans = NIL;
    glob->subroots = NIL;
    glob->rewindPlanIDs = NULL;
    glob->finalrtable = NIL;
    glob->finalrteperminfos = NIL;
    glob->finalrowmarks = NIL;
    glob->resultRelations = NIL;
    glob->appendRelations = NIL;
    glob->relationOids = NIL;
    glob->invalItems = NIL;
    glob->paramExecTypes = NIL;
    glob->lastPHId = 0;
    glob->lastRowMarkId = 0;
    glob->lastPlanNodeId = 0;
    glob->transientPlan = false;
    glob->dependsOnRole = false;

    /* Determine fraction of plan expected to be retrieved */
    if (cursorOptions & CURSOR_OPT_FAST_PLAN)
        tuple_fraction = cursor_tuple_fraction;
    else
        tuple_fraction = 0.0;    /* fetch all tuples */

    /* Set up PlannerInfo data structure for this Query */
    root = subquery_planner(glob, parse,
                           NULL,
                           false, tuple_fraction);

    /* Select best Path and turn it into a Plan */
    final_rel = fetch_upper_rel(root, UPPERREL_FINAL, NULL);
    best_path = get_cheapest_fractional_path(final_rel, tuple_fraction);

    top_plan = create_plan(root, best_path);

    /* ... finalize PlannedStmt ... */

    return result;
}
```

### 4.3 Path Generation

The planner generates multiple alternative "paths" (execution strategies) for each relation and join:

#### Sequential Scan Path

```c
/*
 * create_seqscan_path
 *    Creates a path corresponding to a sequential scan
 */
Path *
create_seqscan_path(PlannerInfo *root, RelOptInfo *rel,
                   Relids required_outer, int parallel_workers)
{
    Path       *pathnode = makeNode(Path);

    pathnode->pathtype = T_SeqScan;
    pathnode->parent = rel;
    pathnode->pathtarget = rel->reltarget;
    pathnode->param_info = get_baserel_parampathinfo(root, rel,
                                                     required_outer);
    pathnode->parallel_aware = (parallel_workers > 0);
    pathnode->parallel_safe = rel->consider_parallel;
    pathnode->parallel_workers = parallel_workers;
    pathnode->pathkeys = NIL;   /* seqscan has unordered result */

    cost_seqscan(pathnode, root, rel, pathnode->param_info);

    return pathnode;
}
```

#### Index Scan Path

```c
/*
 * create_index_path
 *    Creates a path node for an index scan.
 */
IndexPath *
create_index_path(PlannerInfo *root,
                 IndexOptInfo *index,
                 List *indexclauses,
                 List *indexorderbys,
                 List *indexorderbycols,
                 List *pathkeys,
                 ScanDirection indexscandir,
                 bool indexonly,
                 Relids required_outer,
                 double loop_count,
                 bool partial_path)
{
    IndexPath  *pathnode = makeNode(IndexPath);
    RelOptInfo *rel = index->rel;

    pathnode->path.pathtype = indexonly ? T_IndexOnlyScan : T_IndexScan;
    pathnode->path.parent = rel;
    pathnode->path.pathtarget = rel->reltarget;
    pathnode->path.param_info = get_baserel_parampathinfo(root, rel,
                                                          required_outer);
    pathnode->path.parallel_aware = false;
    pathnode->path.parallel_safe = rel->consider_parallel;
    pathnode->path.parallel_workers = 0;
    pathnode->path.pathkeys = pathkeys;

    pathnode->indexinfo = index;
    pathnode->indexclauses = indexclauses;
    pathnode->indexorderbys = indexorderbys;
    pathnode->indexorderbycols = indexorderbycols;
    pathnode->indexscandir = indexscandir;

    cost_index(pathnode, root, loop_count, partial_path);

    return pathnode;
}
```

### 4.4 Join Planning

The planner considers multiple join orders and methods:

**Dynamic Programming Approach** (for small numbers of relations):

```c
/*
 * standard_join_search
 *    Find possible joinpaths for a query by successively finding ways
 *    to join component relations into join relations.
 *
 * We use a dynamic programming approach: for each subset of relations,
 * we find the cheapest way to join them, building up from smaller to
 * larger subsets.  At each level we consider all ways to split the
 * subset into two parts and join them.
 */
RelOptInfo *
standard_join_search(PlannerInfo *root, int levels_needed,
                    List *initial_rels)
{
    int         lev;
    RelOptInfo *rel;

    /*
     * This function would normally be called with levels_needed equal to
     * the number of relations in the query.  The initial_rels list should
     * contain a RelOptInfo for each individual relation in the query.
     */

    /*
     * For each level from 2 to levels_needed, build all possible
     * join combinations.
     */
    for (lev = 2; lev <= levels_needed; lev++)
    {
        ListCell   *lc;

        /*
         * Consider all ways to partition each subset of size lev
         * into two smaller subsets and join them.
         */
        foreach(lc, root->join_rel_level[lev])
        {
            rel = (RelOptInfo *) lfirst(lc);

            /* Try all possible join methods for this combination */
            /* ... */
        }
    }

    /* Return the final join relation representing all tables */
    if (levels_needed == 1)
        return (RelOptInfo *) linitial(initial_rels);
    else
        return (RelOptInfo *) linitial(root->join_rel_level[levels_needed]);
}
```

**Genetic Query Optimization** (for large numbers of relations):

When joining many tables (typically > 12), the planner switches to a genetic algorithm approach:

```c
/*
 * geqo
 *    Genetic Query Optimizer
 *
 * For queries with many relations, exhaustive search becomes impractical.
 * GEQO uses a genetic algorithm to search for good join orders.
 */
RelOptInfo *
geqo(PlannerInfo *root, int number_of_rels, List *initial_rels)
{
    GeqoPrivateData private;
    int         generation;
    Chromosome *momma;
    Chromosome *daddy;

    /* Initialize population with random join orders */
    /* ... */

    /* Evolve population over multiple generations */
    for (generation = 0; generation < number_generations; generation++)
    {
        /* Select parents based on fitness (cost) */
        momma = geqo_selection(&private);
        daddy = geqo_selection(&private);

        /* Create offspring through crossover */
        offspring = gimme_edge_table(momma, daddy);

        /* Apply mutation */
        /* ... */

        /* Replace worst individual if offspring is better */
        /* ... */
    }

    /* Build plan from best chromosome */
    /* ... */
}
```

---

## 5. The Executor

The executor takes a PlannedStmt and executes it, producing result tuples.

### 5.1 Executor Architecture

**Location**: `/home/user/postgres/src/backend/executor/execMain.c` (2,833 lines)

The executor uses a **Volcano-style iterator model** where each plan node implements:

- `ExecInit*` - Initialize the node
- `ExecProc*` - Get next tuple
- `ExecEnd*` - Clean up the node

### 5.2 Executor Lifecycle

```c
/*
 * Executor Interface:
 *
 * ExecutorStart()  - Initialize for execution
 * ExecutorRun()    - Execute the query
 * ExecutorFinish() - Complete execution (trigger AFTER triggers, etc.)
 * ExecutorEnd()    - Shut down and clean up
 */

/* Main execution function */
void
ExecutorStart(QueryDesc *queryDesc, int eflags)
{
    pgstat_report_query_id(queryDesc->plannedstmt->queryId, false);

    if (ExecutorStart_hook)
        (*ExecutorStart_hook) (queryDesc, eflags);
    else
        standard_ExecutorStart(queryDesc, eflags);
}

void
standard_ExecutorStart(QueryDesc *queryDesc, int eflags)
{
    EState     *estate;
    MemoryContext oldcontext;

    /* sanity checks: queryDesc must not be started already */
    Assert(queryDesc != NULL);
    Assert(queryDesc->estate == NULL);

    /*
     * Create the per-query execution state (EState).
     * This includes a memory context for per-query data.
     */
    estate = CreateExecutorState();
    queryDesc->estate = estate;

    oldcontext = MemoryContextSwitchTo(estate->es_query_cxt);

    /* Initialize estate fields */
    estate->es_param_list_info = queryDesc->params;
    estate->es_param_exec_vals = NULL;

    if (queryDesc->plannedstmt->nParamExec > 0)
    {
        estate->es_param_exec_vals = (ParamExecData *)
            palloc0(queryDesc->plannedstmt->nParamExec *
                   sizeof(ParamExecData));
    }

    /* Set up connection to tuple receiver */
    estate->es_processed = 0;
    estate->es_top_eflags = eflags;
    estate->es_instrument = queryDesc->instrument_options;

    /*
     * Initialize the plan state tree
     */
    InitPlan(queryDesc, eflags);

    MemoryContextSwitchTo(oldcontext);
}
```

### 5.3 Tuple Processing Model

**ExecutorRun** - Main execution loop:

```c
void
ExecutorRun(QueryDesc *queryDesc,
           ScanDirection direction, uint64 count,
           bool execute_once)
{
    if (ExecutorRun_hook)
        (*ExecutorRun_hook) (queryDesc, direction, count, execute_once);
    else
        standard_ExecutorRun(queryDesc, direction, count, execute_once);
}

void
standard_ExecutorRun(QueryDesc *queryDesc,
                    ScanDirection direction, uint64 count,
                    bool execute_once)
{
    EState     *estate;
    CmdType     operation;
    DestReceiver *dest;
    bool        sendTuples;
    MemoryContext oldcontext;

    /* sanity checks */
    Assert(queryDesc != NULL);

    estate = queryDesc->estate;
    Assert(estate != NULL);
    Assert(!(estate->es_top_eflags & EXEC_FLAG_EXPLAIN_ONLY));

    /* Switch into per-query memory context */
    oldcontext = MemoryContextSwitchTo(estate->es_query_cxt);

    /* Extract necessary info from queryDesc */
    operation = queryDesc->operation;
    dest = queryDesc->dest;

    /*
     * ExecutePlan processes the plan tree and generates result tuples
     */
    if (queryDesc->plannedstmt->utilityStmt == NULL)
    {
        sendTuples = (operation == CMD_SELECT ||
                     queryDesc->plannedstmt->hasReturning);

        if (sendTuples)
            dest->rStartup(dest, operation, queryDesc->tupDesc);

        ExecutePlan(estate,
                   queryDesc->planstate,
                   queryDesc->plannedstmt->parallelModeNeeded,
                   operation,
                   sendTuples,
                   count,
                   direction,
                   dest,
                   execute_once);

        if (sendTuples)
            dest->rShutdown(dest);
    }

    MemoryContextSwitchTo(oldcontext);
}
```

**ExecutePlan** - Inner execution loop:

```c
static void
ExecutePlan(EState *estate,
           PlanState *planstate,
           bool use_parallel_mode,
           CmdType operation,
           bool sendTuples,
           uint64 numberTuples,
           ScanDirection direction,
           DestReceiver *dest,
           bool execute_once)
{
    TupleTableSlot *slot;
    uint64      current_tuple_count;

    /* Initialize local variables */
    current_tuple_count = 0;

    /*
     * Main execution loop: repeatedly call ExecProcNode to get tuples
     */
    for (;;)
    {
        /* Reset per-tuple memory context */
        ResetPerTupleExprContext(estate);

        /* Get next tuple from plan */
        slot = ExecProcNode(planstate);

        /* If no more tuples, we're done */
        if (TupIsNull(slot))
            break;

        /* Send tuple to destination */
        if (sendTuples)
        {
            if (!dest->receiveSlot(slot, dest))
                break;
        }

        /* Count the tuple */
        current_tuple_count++;
        estate->es_processed++;

        /* Check if we've processed enough tuples */
        if (numberTuples && numberTuples == current_tuple_count)
            break;
    }
}
```

### 5.4 Plan Node Execution

Each plan node type has its own execution function. Example - Sequential Scan:

**Location**: `/home/user/postgres/src/backend/executor/nodeSeqscan.c`

```c
/* ----------------------------------------------------------------
 *		ExecSeqScan(node)
 *
 *		Scans the relation sequentially and returns the next qualifying
 *		tuple.
 *		We call the ExecScan() routine and pass it the appropriate
 *		access method functions.
 * ----------------------------------------------------------------
 */
static TupleTableSlot *
ExecSeqScan(PlanState *pstate)
{
    SeqScanState *node = castNode(SeqScanState, pstate);

    return ExecScan(&node->ss,
                   (ExecScanAccessMtd) SeqNext,
                   (ExecScanRecheckMtd) SeqRecheck);
}

/* ----------------------------------------------------------------
 *		SeqNext
 *
 *		This is a workhorse for ExecSeqScan
 * ----------------------------------------------------------------
 */
static TupleTableSlot *
SeqNext(SeqScanState *node)
{
    HeapScanDesc scandesc;
    TableScanDesc scan;
    EState     *estate;
    ScanDirection direction;
    TupleTableSlot *slot;

    /* Get information from the estate and scan state */
    scandesc = node->ss.ss_currentScanDesc;
    estate = node->ss.ps.state;
    direction = estate->es_direction;
    slot = node->ss.ss_ScanTupleSlot;

    if (scandesc == NULL)
    {
        /* First call - open the scan */
        scandesc = table_beginscan(node->ss.ss_currentRelation,
                                  estate->es_snapshot,
                                  0, NULL);
        node->ss.ss_currentScanDesc = scandesc;
    }

    /* Get the next tuple from the table */
    if (table_scan_getnextslot(scandesc, direction, slot))
        return slot;

    return NULL;  /* No more tuples */
}
```

---

## 6. Catalog System and Syscache

The catalog system stores metadata about database objects. The syscache provides high-speed cached access to catalog tuples.

### 6.1 System Catalogs

PostgreSQL stores all metadata in regular tables (the system catalogs):

- **pg_class** - Tables, indexes, views, sequences
- **pg_attribute** - Columns of tables
- **pg_type** - Data types
- **pg_proc** - Functions and procedures
- **pg_index** - Index definitions
- **pg_operator** - Operators
- **pg_am** - Access methods

**Example Catalog Query**:

```sql
-- Find all columns of a table
SELECT attname, atttypid, attnotnull
FROM pg_attribute
WHERE attrelid = 'employees'::regclass
  AND attnum > 0
  AND NOT attisdropped
ORDER BY attnum;
```

### 6.2 Syscache Architecture

**Location**: `/home/user/postgres/src/backend/utils/cache/syscache.c`

The syscache provides cached access to frequently-accessed catalog tuples:

```c
/*
 * SearchSysCache
 *    A layer on top of SearchCatCache that does the initialization and
 *    key-setting for you.
 *
 * Returns the cache copy of the tuple if one is found, NULL if not.
 * The tuple is the 'cache' copy and must not be modified!
 *
 * When done with a tuple, call ReleaseSysCache().
 */
HeapTuple
SearchSysCache1(int cacheId, Datum key1)
{
    if (cacheId < 0 || cacheId >= SysCacheSize ||
        !PointerIsValid(SysCache[cacheId]))
        elog(ERROR, "invalid cache ID: %d", cacheId);

    return SearchCatCache1(SysCache[cacheId], key1);
}

HeapTuple
SearchSysCache2(int cacheId, Datum key1, Datum key2)
{
    if (cacheId < 0 || cacheId >= SysCacheSize ||
        !PointerIsValid(SysCache[cacheId]))
        elog(ERROR, "invalid cache ID: %d", cacheId);

    return SearchCatCache2(SysCache[cacheId], key1, key2);
}

/* ... similar for SearchSysCache3, SearchSysCache4 ... */

/*
 * ReleaseSysCache
 *    Release previously-fetched syscache tuple
 */
void
ReleaseSysCache(HeapTuple tuple)
{
    ReleaseCatCache(tuple);
}
```

**Common Syscache IDs**:

```c
#define AGGFNOID        0
#define AMNAME          1
#define AMOID           2
#define ATTNAME         3
#define ATTNUM          4
#define AUTHMEMMEMROLE  5
#define AUTHMEMROLEMEM  6
#define AUTHNAME        7
#define AUTHOID         8
#define CLAAMNAMENSP    9
#define CLAOID          10
/* ... 90+ total cache IDs ... */
#define TYPEOID         77
#define RELNAMENSP      35
#define RELOID          36
```

**Usage Example**:

```c
/* Look up a type by OID */
HeapTuple
get_type_tuple(Oid typid)
{
    HeapTuple   tp;

    tp = SearchSysCache1(TYPEOID, ObjectIdGetDatum(typid));
    if (!HeapTupleIsValid(tp))
        elog(ERROR, "cache lookup failed for type %u", typid);

    return tp;
}
```

### 6.3 Relcache

**Location**: `/home/user/postgres/src/backend/utils/cache/relcache.c`

The relation cache stores detailed information about relations (tables, indexes):

```c
/*
 * RelationIdGetRelation
 *    Lookup a relation by OID.  This is a convenience routine that
 *    opens the relation and returns a Relation pointer.
 */
Relation
RelationIdGetRelation(Oid relationId)
{
    Relation    rd;

    /* Check the relcache */
    RelationIdCacheLookup(relationId, rd);

    if (RelationIsValid(rd))
    {
        /* We have a cache hit - bump the refcount */
        RelationIncrementReferenceCount(rd);
        return rd;
    }

    /* No cache hit - need to load the relation descriptor */
    rd = RelationBuildDesc(relationId, true);
    if (RelationIsValid(rd))
        RelationIncrementReferenceCount(rd);

    return rd;
}
```

---

## 7. Node Types and Data Structures

PostgreSQL uses a type-tagged node system for all parse, plan, and execution structures.

### 7.1 Query Node

**Location**: `/home/user/postgres/src/include/nodes/parsenodes.h` (lines 116-200)

```c
/*
 * Query -
 *   Parse analysis turns all statements into a Query tree
 *   for further processing by the rewriter and planner.
 */
typedef struct Query
{
    NodeTag     type;

    CmdType     commandType;    /* select|insert|update|delete|merge|utility */

    QuerySource querySource;    /* where did I come from? */

    int64       queryId;        /* query identifier */

    bool        canSetTag;      /* do I set the command result tag? */

    Node       *utilityStmt;    /* non-null if commandType == CMD_UTILITY */

    int         resultRelation; /* rtable index of target for INSERT/UPDATE/DELETE */

    /* Flags indicating presence of various constructs */
    bool        hasAggs;        /* has aggregates in tlist or havingQual */
    bool        hasWindowFuncs; /* has window functions in tlist */
    bool        hasTargetSRFs;  /* has set-returning functions in tlist */
    bool        hasSubLinks;    /* has subquery SubLink */
    bool        hasDistinctOn;  /* distinctClause is from DISTINCT ON */
    bool        hasRecursive;   /* WITH RECURSIVE was specified */
    bool        hasModifyingCTE;/* has INSERT/UPDATE/DELETE in WITH */
    bool        hasForUpdate;   /* FOR [KEY] UPDATE/SHARE was specified */
    bool        hasRowSecurity; /* rewriter has applied some RLS policy */

    List       *cteList;        /* WITH list (of CommonTableExpr's) */

    List       *rtable;         /* list of range table entries */
    List       *rteperminfos;   /* list of RTEPermissionInfo nodes */
    FromExpr   *jointree;       /* table join tree (FROM and WHERE clauses) */

    List       *targetList;     /* target list (of TargetEntry) */

    OverridingKind override;    /* OVERRIDING clause */

    OnConflictExpr *onConflict; /* ON CONFLICT DO [NOTHING | UPDATE] */

    List       *returningList;  /* return-values list (of TargetEntry) */

    List       *groupClause;    /* a list of SortGroupClause's */
    bool        groupDistinct;  /* is the group by clause distinct? */

    List       *groupingSets;   /* a list of GroupingSet's if present */

    Node       *havingQual;     /* qualifications applied to groups */

    List       *windowClause;   /* a list of WindowClause's */

    List       *distinctClause; /* a list of SortGroupClause's */

    List       *sortClause;     /* a list of SortGroupClause's */

    Node       *limitOffset;    /* # of result tuples to skip (int8 expr) */
    Node       *limitCount;     /* # of result tuples to return (int8 expr) */
    LimitOption limitOption;    /* limit type */

    List       *rowMarks;       /* a list of RowMarkClause's */

    Node       *setOperations;  /* set-operation tree if this is top level of
                                 * a UNION/INTERSECT/EXCEPT query */

    List       *constraintDeps; /* a list of pg_constraint OIDs */

    List       *withCheckOptions;   /* a list of WithCheckOption's */

    int         stmt_location;  /* start location, or -1 if unknown */
    int         stmt_len;       /* length in bytes; 0 means "rest of string" */
} Query;
```

### 7.2 Plan Node

**Location**: `/home/user/postgres/src/include/nodes/plannodes.h` (lines 184-220)

```c
/*
 * Plan node
 *
 * All plan nodes "derive" from the Plan structure by having the
 * Plan structure as the first field.
 */
typedef struct Plan
{
    NodeTag     type;

    /*
     * Estimated execution costs for plan (see costsize.c for more info)
     */
    int         disabled_nodes; /* count of disabled nodes */
    Cost        startup_cost;   /* cost expended before fetching any tuples */
    Cost        total_cost;     /* total cost (assuming all tuples fetched) */

    /*
     * Planner's estimate of result size
     */
    double      plan_rows;      /* number of rows plan is expected to emit */
    int         plan_width;     /* average row width in bytes */

    /*
     * Information for parallel query
     */
    bool        parallel_aware; /* engage parallel-aware logic? */
    bool        parallel_safe;  /* OK to use as part of parallel plan? */

    /*
     * Common structural data for all Plan types.
     */
    int         plan_node_id;   /* unique across entire final plan tree */
    List       *targetlist;     /* target list to be computed at this node */
    List       *qual;           /* implicitly-ANDed qual conditions */
    struct Plan *lefttree;      /* input plan tree(s) */
    struct Plan *righttree;
    List       *initPlan;       /* Init SubPlan nodes (un-correlated expr subselects) */

    /*
     * Information for management of parameter-change-driven rescanning
     */
    Bitmapset  *extParam;       /* indices of _all_ ext params in plan */
    Bitmapset  *allParam;       /* indices of all ext+exec params in plan */
} Plan;
```

### 7.3 PlanState Node

**Location**: `/home/user/postgres/src/include/nodes/execnodes.h` (lines 1095-1150)

```c
/* ----------------
 *  PlanState node
 *
 * We never actually instantiate any PlanState nodes; this is just the common
 * abstract superclass for all PlanState-type nodes.
 * ----------------
 */
typedef struct PlanState
{
    NodeTag     type;

    Plan       *plan;           /* associated Plan node */

    EState     *state;          /* executor state node */

    ExecProcNodeMtd ExecProcNode;   /* function to fetch next tuple */
    ExecProcNodeMtd ExecProcNodeReal;

    Instrumentation *instrument;    /* Optional runtime stats for this node */
    WorkerInstrumentation *worker_instrument;   /* per-worker instrumentation */

    /* Per-worker JIT instrumentation */
    struct SharedJitInstrumentation *worker_jit_instrument;

    /* Identify node for EXPLAIN */
    char       *nodename;

    /*
     * Common structural data for all Plan types.
     */
    ExprState  *qual;           /* boolean qual condition */
    struct PlanState *lefttree; /* input plan tree(s) */
    struct PlanState *righttree;

    List       *initPlan;       /* Init SubPlanState nodes */

    List       *subPlan;        /* SubPlanState nodes in my expressions */

    /*
     * State for management of parameter-change-driven rescanning
     */
    Bitmapset  *chgParam;       /* set of IDs of changed Params */

    /*
     * Tuple table for this plan node
     */
    TupleTableSlot *ps_ResultTupleSlot;

    /*
     * Tuple descriptor for the result tuples
     */
    TupleDesc   ps_ResultTupleDesc;

    /* Slot for storing projection result */
    TupleTableSlot *ps_ProjInfo;

    /*
     * Node's current tuple, if it's a scan node
     */
    bool        scandesc_created;   /* scanstate has created scan descriptor */
    bool        scanops_inited;     /* scanops have been inited */
} PlanState;
```

### 7.4 Specialized Plan Nodes

**Sequential Scan**:

```c
typedef struct SeqScan
{
    Scan        scan;
} SeqScan;
```

**Index Scan**:

```c
typedef struct IndexScan
{
    Scan        scan;
    Oid         indexid;        /* OID of index to scan */
    List       *indexqual;      /* list of index quals (usually OpExprs) */
    List       *indexqualorig;  /* the same in original form */
    List       *indexorderby;   /* list of index ORDER BY exprs */
    List       *indexorderbyorig;
    List       *indexorderbyops;/* OIDs of sort ops for ORDER BY exprs */
    ScanDirection indexorderdir;/* forward or backward */
} IndexScan;
```

**Nested Loop Join**:

```c
typedef struct NestLoop
{
    Join        join;
    List       *nestParams;     /* list of NestLoopParam nodes */
} NestLoop;

typedef struct NestLoopParam
{
    NodeTag     type;
    int         paramno;        /* number of the PARAM_EXEC Param to set */
    Var        *paramval;       /* outer-relation Var to assign to Param */
} NestLoopParam;
```

---

## 8. Join Algorithms

PostgreSQL implements three fundamental join algorithms, each optimal for different scenarios.

### 8.1 Nested Loop Join

**Best for**: Small inner relation, or when join has very high selectivity

**Algorithm**:
```
For each row R in outer relation:
    For each row S in inner relation:
        If join_condition(R, S):
            Output combined row
```

**Implementation**: `/home/user/postgres/src/backend/executor/nodeNestloop.c`

```c
/* ----------------------------------------------------------------
 *   ExecNestLoop(node)
 *
 * Returns a tuple from nested loop join or NULL if done.
 * ----------------------------------------------------------------
 */
static TupleTableSlot *
ExecNestLoop(PlanState *pstate)
{
    NestLoopState *node = castNode(NestLoopState, pstate);
    NestLoop   *nl;
    PlanState  *innerPlan;
    PlanState  *outerPlan;
    TupleTableSlot *outerTupleSlot;
    TupleTableSlot *innerTupleSlot;
    ExprState  *joinqual;
    ExprState  *otherqual;
    ExprContext *econtext;
    ListCell   *lc;

    /* Get information from the node */
    nl = (NestLoop *) node->js.ps.plan;
    joinqual = node->js.joinqual;
    otherqual = node->js.ps.qual;
    outerPlan = outerPlanState(node);
    innerPlan = innerPlanState(node);
    econtext = node->js.ps.ps_ExprContext;

    /* Reset per-tuple memory context to free expression results */
    ResetExprContext(econtext);

    /*
     * If we don't have an outer tuple, get the next one
     */
    if (node->nl_NeedNewOuter)
    {
        outerTupleSlot = ExecProcNode(outerPlan);

        /* No more outer tuples means we're done */
        if (TupIsNull(outerTupleSlot))
            return NULL;

        econtext->ecxt_outertuple = outerTupleSlot;
        node->nl_NeedNewOuter = false;
        node->nl_MatchedOuter = false;

        /*
         * Set nestloop parameters from outer tuple
         */
        foreach(lc, nl->nestParams)
        {
            NestLoopParam *nlp = (NestLoopParam *) lfirst(lc);
            int         paramno = nlp->paramno;
            ParamExecData *prm;

            prm = &(econtext->ecxt_param_exec_vals[paramno]);
            /* Get value from outer tuple */
            prm->value = ExecEvalExpr(nlp->paramval, econtext,
                                     &(prm->isnull));
            innerPlan->chgParam = bms_add_member(innerPlan->chgParam,
                                                paramno);
        }

        /* Rescan inner plan for new outer tuple */
        ExecReScan(innerPlan);
    }

    /*
     * Main loop: fetch tuples from inner side and test join condition
     */
    for (;;)
    {
        /* Get next inner tuple */
        innerTupleSlot = ExecProcNode(innerPlan);

        /* No more inner tuples for this outer tuple */
        if (TupIsNull(innerTupleSlot))
        {
            node->nl_NeedNewOuter = true;

            /* Handle outer join */
            if (!node->nl_MatchedOuter &&
                (node->js.jointype == JOIN_LEFT ||
                 node->js.jointype == JOIN_ANTI))
            {
                /* Emit null-extended tuple */
                /* ... */
            }

            /* Get next outer tuple */
            outerTupleSlot = ExecProcNode(outerPlan);
            if (TupIsNull(outerTupleSlot))
                return NULL;

            econtext->ecxt_outertuple = outerTupleSlot;
            node->nl_MatchedOuter = false;

            /* Rescan inner plan */
            ExecReScan(innerPlan);
            continue;
        }

        /* Test the join condition */
        econtext->ecxt_innertuple = innerTupleSlot;

        if (ExecQual(joinqual, econtext))
        {
            node->nl_MatchedOuter = true;

            /* Test additional quals */
            if (otherqual == NULL || ExecQual(otherqual, econtext))
            {
                /* We have a match! */
                return ExecProject(node->js.ps.ps_ProjInfo);
            }
        }
    }
}
```

**Complexity**: O(N × M) where N = outer rows, M = inner rows

### 8.2 Hash Join

**Best for**: Large relations with equijoin conditions

**Algorithm**:
```
Build Phase:
    Create hash table from inner relation

Probe Phase:
    For each row R in outer relation:
        Hash R's join key
        Lookup matching rows in hash table
        Output matches
```

**Implementation**: `/home/user/postgres/src/backend/executor/nodeHashjoin.c`

```c
/* ----------------------------------------------------------------
 *   ExecHashJoin
 *
 * Parallel-aware hash join executor entry point.
 * ----------------------------------------------------------------
 */
static TupleTableSlot *
ExecHashJoin(PlanState *pstate)
{
    HashJoinState *node = castNode(HashJoinState, pstate);
    PlanState  *outerPlan;
    HashState  *hashNode;
    ExprState  *joinqual;
    ExprState  *otherqual;
    ExprContext *econtext;
    HashJoinTable hashtable;
    TupleTableSlot *outerTupleSlot;
    uint32      hashvalue;
    int         batchno;

    /* Get state from node */
    joinqual = node->js.joinqual;
    otherqual = node->js.ps.qual;
    hashNode = (HashState *) innerPlanState(node);
    outerPlan = outerPlanState(node);
    hashtable = node->hj_HashTable;
    econtext = node->js.ps.ps_ExprContext;

    /* Reset per-tuple memory context */
    ResetExprContext(econtext);

    /*
     * If we're doing a right/full outer join, we need to track
     * which inner tuples have been matched
     */

    /* Main execution loop */
    for (;;)
    {
        switch (node->hj_JoinState)
        {
            case HJ_BUILD_HASHTABLE:
                /* Build the hash table from inner relation */
                hashtable = ExecHashTableCreate(hashNode,
                                               node->hj_HashOperators,
                                               HJ_FILL_OUTER(node));
                node->hj_HashTable = hashtable;

                /* Execute inner plan to populate hash table */
                /* ... */

                node->hj_JoinState = HJ_NEED_NEW_OUTER;
                /* FALL THRU */

            case HJ_NEED_NEW_OUTER:
                /* Get next outer tuple */
                outerTupleSlot = ExecProcNode(outerPlan);
                if (TupIsNull(outerTupleSlot))
                {
                    /* No more outer tuples */
                    node->hj_JoinState = HJ_NEED_NEW_BATCH;
                    continue;
                }

                econtext->ecxt_outertuple = outerTupleSlot;

                /* Compute hash value for outer tuple */
                if (HJ_FILL_INNER(node))
                    node->hj_MatchedOuter = false;

                hashvalue = ExecHashGetHashValue(hashtable,
                                                econtext,
                                                node->hj_OuterHashKeys);

                node->hj_CurHashValue = hashvalue;
                node->hj_CurBucketNo = ExecHashGetBucketAndBatch(hashtable,
                                                                hashvalue,
                                                                &batchno,
                                                                &node->hj_CurSkewBucketNo);
                node->hj_CurTuple = NULL;
                node->hj_JoinState = HJ_SCAN_BUCKET;
                /* FALL THRU */

            case HJ_SCAN_BUCKET:
                /* Scan hash bucket for matches */
                for (;;)
                {
                    if (node->hj_CurTuple == NULL)
                    {
                        /* Get first/next tuple from bucket */
                        node->hj_CurTuple = ExecScanHashBucket(node,
                                                              econtext);
                        if (node->hj_CurTuple == NULL)
                        {
                            /* No more tuples in bucket */
                            node->hj_JoinState = HJ_NEED_NEW_OUTER;
                            break;
                        }
                    }

                    /* Test join condition */
                    if (joinqual == NULL || ExecQual(joinqual, econtext))
                    {
                        node->hj_MatchedOuter = true;

                        /* Test additional quals */
                        if (otherqual == NULL || ExecQual(otherqual, econtext))
                        {
                            /* Found a match! */
                            return ExecProject(node->js.ps.ps_ProjInfo);
                        }
                    }

                    /* Try next tuple in bucket */
                    node->hj_CurTuple = NULL;
                }
                break;

            case HJ_NEED_NEW_BATCH:
                /* Handle additional batches for large datasets */
                /* ... */
                return NULL;

            default:
                elog(ERROR, "unrecognized hashjoin state: %d",
                     (int) node->hj_JoinState);
        }
    }
}
```

**Complexity**: O(N + M) average case (with good hash function)

**Space**: O(M) for hash table

### 8.3 Merge Join

**Best for**: Both inputs already sorted on join key, or sort would be beneficial for other reasons

**Algorithm**:
```
Sort both relations on join key (if not already sorted)

Scan both relations in parallel:
    If left.key < right.key:
        Advance left
    Else if left.key > right.key:
        Advance right
    Else:  /* Keys match */
        Output all matching combinations
        Advance both when done with this key value
```

**Data Structure** (from plannodes.h, lines 1014-1040):

```c
/* ----------------
 *   merge join node
 *
 * The expected ordering of each mergeable column is described by a btree
 * opfamily OID, a collation OID, a direction (BTLessStrategyNumber or
 * BTGreaterStrategyNumber) and a nulls-first flag.
 * ----------------
 */
typedef struct MergeJoin
{
    Join        join;

    bool        skip_mark_restore; /* Can we skip mark/restore calls? */

    List       *mergeclauses;   /* mergeclauses as expression trees */

    /* these are arrays, but have the same length as the mergeclauses list: */

    Oid        *mergeFamilies;  /* per-clause OIDs of btree opfamilies */
    Oid        *mergeCollations;/* per-clause OIDs of collations */
    int        *mergeStrategies;/* per-clause ordering (ASC or DESC) */
    bool       *mergeNullsFirst;/* per-clause nulls ordering */
} MergeJoin;
```

**Implementation**: `/home/user/postgres/src/backend/executor/nodeMergejoin.c`

**Complexity**: O(N log N + M log M) if sorting needed, O(N + M) if pre-sorted

---

## 9. Cost Model and Parameters

PostgreSQL's cost-based optimizer estimates the cost of each plan using a parameterized cost model.

### 9.1 Cost Parameters

**Location**: `/home/user/postgres/src/backend/optimizer/path/costsize.c` (lines 130-134)

```c
/* GUC cost parameters */
double      seq_page_cost = DEFAULT_SEQ_PAGE_COST;         /* 1.0 */
double      random_page_cost = DEFAULT_RANDOM_PAGE_COST;   /* 4.0 */
double      cpu_tuple_cost = DEFAULT_CPU_TUPLE_COST;       /* 0.01 */
double      cpu_index_tuple_cost = DEFAULT_CPU_INDEX_TUPLE_COST;   /* 0.005 */
double      cpu_operator_cost = DEFAULT_CPU_OPERATOR_COST; /* 0.0025 */
double      parallel_tuple_cost = DEFAULT_PARALLEL_TUPLE_COST;     /* 0.1 */
double      parallel_setup_cost = DEFAULT_PARALLEL_SETUP_COST;     /* 1000.0 */
```

**Parameter Meanings**:

- **seq_page_cost**: Cost of a sequential page fetch (default: 1.0)
- **random_page_cost**: Cost of a non-sequential page fetch (default: 4.0)
- **cpu_tuple_cost**: Cost to process one tuple (default: 0.01)
- **cpu_index_tuple_cost**: Cost to process one index entry (default: 0.005)
- **cpu_operator_cost**: Cost to execute an operator/function (default: 0.0025)

### 9.2 Sequential Scan Costing

**From costsize.c (lines 260-310)**:

```c
/*
 * cost_seqscan
 *   Determines and returns the cost of scanning a relation sequentially.
 *
 * 'baserel' is the relation to be scanned
 * 'param_info' is the ParamPathInfo if this is a parameterized path, else NULL
 */
void
cost_seqscan(Path *path, PlannerInfo *root,
            RelOptInfo *baserel, ParamPathInfo *param_info)
{
    Cost        startup_cost = 0;
    Cost        cpu_run_cost;
    Cost        disk_run_cost;
    double      spc_seq_page_cost;
    QualCost    qpqual_cost;
    Cost        cpu_per_tuple;

    /* Should only be applied to base relations */
    Assert(baserel->relid > 0);
    Assert(baserel->rtekind == RTE_RELATION);

    /* Mark the path with the correct row estimate */
    if (param_info)
        path->rows = param_info->ppi_rows;
    else
        path->rows = baserel->rows;

    if (!enable_seqscan)
        startup_cost += disable_cost;

    /* Get tablespace-specific page cost */
    get_tablespace_page_costs(baserel->reltablespace,
                             NULL,
                             &spc_seq_page_cost);

    /*
     * Disk cost: pages × cost per sequential page
     */
    disk_run_cost = spc_seq_page_cost * baserel->pages;

    /* CPU cost: tuples × (base cost + qual evaluation cost) */
    get_restriction_qual_cost(root, baserel, param_info, &qpqual_cost);

    startup_cost += qpqual_cost.startup;
    cpu_per_tuple = cpu_tuple_cost + qpqual_cost.per_tuple;
    cpu_run_cost = cpu_per_tuple * baserel->tuples;

    /* Total cost */
    path->startup_cost = startup_cost;
    path->total_cost = startup_cost + cpu_run_cost + disk_run_cost;
}
```

**Formula**:
```
Startup Cost = qual_startup_cost
Total Cost = startup_cost +
             (pages × seq_page_cost) +
             (tuples × (cpu_tuple_cost + qual_per_tuple_cost))
```

### 9.3 Index Scan Costing

```c
/*
 * cost_index
 *   Determines and returns the cost of scanning a relation using an index.
 *
 * 'path' describes the indexscan under consideration, and is complete
 *       except for the fields to be set by this routine
 * 'loop_count' is the number of repetitions of the indexscan to factor into
 *       estimates of caching behavior
 */
void
cost_index(IndexPath *path, PlannerInfo *root, double loop_count,
          bool partial_path)
{
    IndexOptInfo *index = path->indexinfo;
    RelOptInfo *baserel = index->rel;
    List       *qpquals;
    Cost        startup_cost = 0;
    Cost        run_cost = 0;
    Cost        cpu_run_cost = 0;
    Cost        indexStartupCost;
    Cost        indexTotalCost;
    Selectivity indexSelectivity;
    double      indexCorrelation;
    double      csquared;
    double      spc_random_page_cost;
    Cost        min_IO_cost,
                max_IO_cost;
    QualCost    qpqual_cost;
    Cost        cpu_per_tuple;
    double      tuples_fetched;
    double      pages_fetched;

    /* ... complex index cost calculation ... */

    /*
     * Estimate number of main-table pages fetched
     */
    tuples_fetched = clamp_row_est(indexSelectivity * baserel->tuples);

    /* Account for index correlation */
    pages_fetched = index_pages_fetched(tuples_fetched,
                                       baserel->pages,
                                       (double) index->pages,
                                       root);

    /*
     * Random access is more expensive than sequential
     */
    if (loop_count > 1)
    {
        /* Multiple iterations - assume some caching */
        pages_fetched = index_pages_fetched(tuples_fetched,
                                           baserel->pages,
                                           (double) index->pages,
                                           root);
        /* Adjust for caching */
        pages_fetched = pages_fetched * sqrt(loop_count);
    }

    /* I/O cost */
    run_cost += pages_fetched * spc_random_page_cost;

    /* CPU cost */
    cpu_per_tuple = cpu_tuple_cost + qpqual_cost.per_tuple;
    run_cost += cpu_per_tuple * tuples_fetched;

    path->path.startup_cost = startup_cost;
    path->path.total_cost = startup_cost + run_cost;
}
```

### 9.4 Join Costing

**Nested Loop**:
```
Cost = outer_cost +
       (outer_rows × inner_cost) +
       (outer_rows × inner_rows × cpu_tuple_cost)
```

**Hash Join**:
```
Cost = outer_cost +
       inner_cost +
       (hash_build_cost) +
       (outer_rows × cpu_operator_cost) +  /* hash probe */
       (matched_rows × cpu_tuple_cost)      /* join processing */
```

**Merge Join**:
```
Cost = outer_sort_cost +
       inner_sort_cost +
       (outer_rows + inner_rows) × cpu_operator_cost  /* merge */
```

### 9.5 Selectivity Estimation

The optimizer estimates what fraction of rows satisfy a condition:

```c
/*
 * clauselist_selectivity -
 *   Compute the selectivity of an implicitly-ANDed list of boolean
 *   expression clauses.  The list can be empty, in which case 1.0
 *   should be returned.
 */
Selectivity
clauselist_selectivity(PlannerInfo *root,
                      List *clauses,
                      int varRelid,
                      JoinType jointype,
                      SpecialJoinInfo *sjinfo)
{
    Selectivity s1 = 1.0;
    ListCell   *l;

    foreach(l, clauses)
    {
        Node       *clause = (Node *) lfirst(l);
        Selectivity s2;

        /* Estimate selectivity of this clause */
        s2 = clause_selectivity(root, clause, varRelid, jointype, sjinfo);

        /* Combine estimates (assumes independence) */
        s1 = s1 * s2;
    }

    return s1;
}
```

**Common Selectivity Estimates**:
- `col = constant`: 1 / n_distinct(col)
- `col > constant`: Depends on histogram
- `col IS NULL`: null_frac statistic
- `col LIKE 'prefix%'`: Pattern-based estimate

---

## 10. Expression Evaluation

PostgreSQL compiles expressions into a bytecode-like format for efficient evaluation.

### 10.1 ExprState Structure

**Location**: `/home/user/postgres/src/include/nodes/execnodes.h` (lines 83-147)

```c
typedef struct ExprState
{
    NodeTag     type;

    uint8       flags;          /* bitmask of EEO_FLAG_* bits */

    bool        resnull;        /* current null flag for result */
    Datum       resvalue;       /* current value for result */

    TupleTableSlot *resultslot; /* slot for result if projecting a tuple */

    struct ExprEvalStep *steps; /* array of execution steps */

    ExprStateEvalFunc evalfunc; /* function to actually evaluate expression */

    Expr       *expr;           /* original expression tree (for debugging) */

    void       *evalfunc_private;   /* private state for evalfunc */

    /* Fields used during compilation */
    int         steps_len;      /* number of steps currently */
    int         steps_alloc;    /* allocated length of steps array */

    PlanState  *parent;         /* parent PlanState node, if any */
    ParamListInfo ext_params;   /* for compiling PARAM_EXTERN nodes */

    Datum      *innermost_caseval;
    bool       *innermost_casenull;

    Datum      *innermost_domainval;
    bool       *innermost_domainnull;
} ExprState;
```

### 10.2 Expression Compilation

**Location**: `/home/user/postgres/src/backend/executor/execExpr.c`

```c
/*
 * ExecInitExpr: prepare an expression tree for execution
 *
 * This function builds an ExprState tree describing the computation
 * that needs to be performed for the given Expr node tree.
 */
ExprState *
ExecInitExpr(Expr *node, PlanState *parent)
{
    ExprState  *state;
    ExprEvalStep scratch = {0};

    /* Allocate ExprState */
    state = makeNode(ExprState);
    state->expr = node;
    state->parent = parent;
    state->ext_params = NULL;

    /* Initialize step array */
    state->steps_len = 0;
    state->steps_alloc = 16;
    state->steps = palloc(state->steps_alloc * sizeof(ExprEvalStep));

    /* Compile expression into steps */
    ExecInitExprRec(node, state, &state->resvalue, &state->resnull);

    /* Add final step */
    scratch.opcode = EEOP_DONE;
    ExprEvalPushStep(state, &scratch);

    /* Set evaluation function */
    ExecReadyExpr(state);

    return state;
}
```

### 10.3 Expression Steps

Expressions are compiled into a sequence of steps:

```c
typedef enum ExprEvalOp
{
    /* Entire expression has been evaluated */
    EEOP_DONE,

    /* Push a NULL onto the stack */
    EEOP_CONST,

    /* Fetch a parameter value */
    EEOP_PARAM_EXTERN,
    EEOP_PARAM_EXEC,

    /* Fetch a column from a tuple */
    EEOP_SCAN_FETCHSOME,
    EEOP_SCAN_VAR,
    EEOP_INNER_VAR,
    EEOP_OUTER_VAR,

    /* Evaluate a function call */
    EEOP_FUNCEXPR,
    EEOP_FUNCEXPR_STRICT,

    /* Boolean operators */
    EEOP_BOOL_AND_STEP_FIRST,
    EEOP_BOOL_AND_STEP,
    EEOP_BOOL_OR_STEP_FIRST,
    EEOP_BOOL_OR_STEP,
    EEOP_BOOL_NOT_STEP,

    /* Operators */
    EEOP_QUAL,
    EEOP_JUMP,
    EEOP_JUMP_IF_NULL,
    EEOP_JUMP_IF_NOT_NULL,
    EEOP_JUMP_IF_NOT_TRUE,

    /* Aggregates */
    EEOP_AGG_STRICT_DESERIALIZE,
    EEOP_AGG_DESERIALIZE,
    EEOP_AGG_STRICT_INPUT_CHECK_ARGS,
    EEOP_AGG_STRICT_INPUT_CHECK_NULLS,

    /* ... many more opcodes ... */
} ExprEvalOp;
```

### 10.4 JIT Compilation

For frequently-executed expressions, PostgreSQL can use LLVM for JIT compilation:

```c
/*
 * llvm_compile_expr -
 *   JIT compile an expression
 */
static void
llvm_compile_expr(ExprState *state)
{
    PlanState  *parent = state->parent;
    LLVMJitContext *context;
    LLVMModuleRef mod;
    char       *funcname;

    /* Initialize LLVM context */
    context = llvm_create_context(parent->state->es_jit_flags);

    /* Create LLVM module for this expression */
    mod = llvm_mutable_module(context);

    /* Compile each step into LLVM IR */
    /* ... */

    /* Optimize and finalize */
    llvm_optimize_module(context, mod);

    /* Replace interpreted eval function with JIT-compiled version */
    state->evalfunc = (ExprStateEvalFunc) llvm_get_function(context, funcname);
}
```

---

## 11. Complete Query Example Walkthrough

Let's walk through the complete processing of a moderately complex query:

### 11.1 Example Query

```sql
SELECT e.name, e.salary, d.dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE e.salary > 50000
  AND d.location = 'New York'
ORDER BY e.salary DESC
LIMIT 10;
```

### 11.2 Stage 1: Parsing

**Input**: SQL text string

**Lexer Output** (token stream):
```
SELECT, IDENT(e), DOT, IDENT(name), COMMA,
IDENT(e), DOT, IDENT(salary), COMMA,
IDENT(d), DOT, IDENT(dept_name),
FROM, IDENT(employees), IDENT(e),
JOIN, IDENT(departments), IDENT(d),
ON, IDENT(e), DOT, IDENT(dept_id), EQUALS, IDENT(d), DOT, IDENT(dept_id),
WHERE, IDENT(e), DOT, IDENT(salary), GREATER, ICONST(50000),
AND, IDENT(d), DOT, IDENT(location), EQUALS, SCONST('New York'),
ORDER, BY, IDENT(e), DOT, IDENT(salary), DESC,
LIMIT, ICONST(10), SEMICOLON
```

**Parser Output** (SelectStmt):
```
SelectStmt {
    targetList: [
        ResTarget { val: ColumnRef([e, name]) },
        ResTarget { val: ColumnRef([e, salary]) },
        ResTarget { val: ColumnRef([d, dept_name]) }
    ],
    fromClause: [
        JoinExpr {
            jointype: JOIN_INNER,
            larg: RangeVar { relname: "employees", alias: "e" },
            rarg: RangeVar { relname: "departments", alias: "d" },
            quals: A_Expr {
                kind: AEXPR_OP,
                name: "=",
                lexpr: ColumnRef([e, dept_id]),
                rexpr: ColumnRef([d, dept_id])
            }
        }
    ],
    whereClause: BoolExpr {
        boolop: AND_EXPR,
        args: [
            A_Expr { /* e.salary > 50000 */ },
            A_Expr { /* d.location = 'New York' */ }
        ]
    },
    sortClause: [
        SortBy { node: ColumnRef([e, salary]), sortby_dir: DESC }
    ],
    limitCount: A_Const { val: 10 }
}
```

**Analyzer Output** (Query):
```c
Query {
    commandType: CMD_SELECT,

    rtable: [
        RangeTblEntry {  /* #1: employees */
            rtekind: RTE_RELATION,
            relid: <OID of employees>,
            alias: "e",
            requiredPerms: ACL_SELECT
        },
        RangeTblEntry {  /* #2: departments */
            rtekind: RTE_RELATION,
            relid: <OID of departments>,
            alias: "d",
            requiredPerms: ACL_SELECT
        }
    ],

    jointree: FromExpr {
        fromlist: [
            JoinExpr {
                jointype: JOIN_INNER,
                larg: RangeTblRef { rtindex: 1 },  /* employees */
                rarg: RangeTblRef { rtindex: 2 },  /* departments */
                quals: OpExpr {
                    opno: <OID of int4eq>,
                    args: [
                        Var { varno: 1, varattno: 3 },  /* e.dept_id */
                        Var { varno: 2, varattno: 1 }   /* d.dept_id */
                    ]
                }
            }
        ],
        quals: BoolExpr {
            boolop: AND_EXPR,
            args: [
                OpExpr {  /* e.salary > 50000 */
                    opno: <OID of int4gt>,
                    args: [
                        Var { varno: 1, varattno: 2 },
                        Const { consttype: INT4, constvalue: 50000 }
                    ]
                },
                OpExpr {  /* d.location = 'New York' */
                    opno: <OID of texteq>,
                    args: [
                        Var { varno: 2, varattno: 3 },
                        Const { consttype: TEXT, constvalue: "New York" }
                    ]
                }
            ]
        }
    },

    targetList: [
        TargetEntry {
            expr: Var { varno: 1, varattno: 1, vartype: TEXT },
            resname: "name"
        },
        TargetEntry {
            expr: Var { varno: 1, varattno: 2, vartype: INT4 },
            resname: "salary"
        },
        TargetEntry {
            expr: Var { varno: 2, varattno: 2, vartype: TEXT },
            resname: "dept_name"
        }
    ],

    sortClause: [
        SortGroupClause {
            tleSortGroupRef: 2,  /* salary */
            sortop: <OID of int4gt>,  /* DESC */
            nulls_first: false
        }
    ],

    limitCount: Const { consttype: INT8, constvalue: 10 }
}
```

### 11.3 Stage 2: Rewriting

In this case, no views or rules are involved, so the rewriter passes the query through unchanged (after checking for any applicable RLS policies).

### 11.4 Stage 3: Planning

**Planner generates multiple paths**:

**Path 1: Hash Join**
```
Limit (10 rows)
  → Sort (salary DESC)
    → Hash Join (e.dept_id = d.dept_id)
      ├─ Seq Scan on employees
      │  Filter: salary > 50000
      │  Cost: 0..1000, Rows: 5000
      └─ Hash
        └─ Seq Scan on departments
           Filter: location = 'New York'
           Cost: 0..100, Rows: 5
```

**Cost Calculation**:
```
Employees Seq Scan:
  - Pages: 100, Tuples: 10000
  - Cost = 100 × 1.0 + 10000 × 0.01 = 200
  - After filter (50%): 5000 rows

Departments Seq Scan:
  - Pages: 10, Tuples: 50
  - Cost = 10 × 1.0 + 50 × 0.01 = 10.5
  - After filter (10%): 5 rows

Hash Build:
  - Cost = 5 × 0.01 = 0.05

Hash Join:
  - Probe cost: 5000 × 0.0025 = 12.5
  - Match processing: ~100 matches × 0.01 = 1
  - Total: 200 + 10.5 + 0.05 + 12.5 + 1 = 224.05

Sort:
  - 100 rows × log(100) × 0.01 = ~6.64

Limit:
  - Negligible

Total: ~230.69
```

**Path 2: Index Nested Loop** (if index exists on departments.location):
```
Limit (10 rows)
  → Sort (salary DESC)
    → Nested Loop
      ├─ Index Scan on departments using dept_location_idx
      │  Index Cond: location = 'New York'
      │  Cost: 0..20, Rows: 5
      └─ Index Scan on employees using emp_dept_idx
         Index Cond: dept_id = d.dept_id
         Filter: salary > 50000
         Cost: 0..50 per loop, Rows: 20
```

**Planner selects best path** (assume Hash Join is cheaper)

**Final PlannedStmt**:
```c
PlannedStmt {
    commandType: CMD_SELECT,
    planTree: Limit {
        plan: {
            startup_cost: 224.05,
            total_cost: 230.69,
            plan_rows: 10,
            plan_width: 44
        },
        limitCount: Const { value: 10 },
        lefttree: Sort {
            plan: {
                startup_cost: 224.05,
                total_cost: 230.64,
                plan_rows: 100,
                plan_width: 44
            },
            sortColIdx: [2],  /* salary column */
            sortOperators: [<OID of int4gt>],
            lefttree: HashJoin {
                plan: {
                    startup_cost: 10.55,
                    total_cost: 224.05,
                    plan_rows: 100,
                    plan_width: 44
                },
                hashclauses: [
                    OpExpr {
                        opno: <OID of int4eq>,
                        args: [Var(1,3), Var(2,1)]
                    }
                ],
                lefttree: SeqScan {  /* employees */
                    plan: {
                        startup_cost: 0,
                        total_cost: 200,
                        plan_rows: 5000,
                        plan_width: 36
                    },
                    scanrelid: 1,
                    qual: [
                        OpExpr { /* salary > 50000 */ }
                    ]
                },
                righttree: Hash {
                    plan: {
                        startup_cost: 10.5,
                        total_cost: 10.5,
                        plan_rows: 5,
                        plan_width: 12
                    },
                    lefttree: SeqScan {  /* departments */
                        plan: {
                            startup_cost: 0,
                            total_cost: 10.5,
                            plan_rows: 5,
                            plan_width: 12
                        },
                        scanrelid: 2,
                        qual: [
                            OpExpr { /* location = 'New York' */ }
                        ]
                    }
                }
            }
        }
    }
}
```

### 11.5 Stage 4: Execution

**ExecutorStart** initializes the plan tree:

```
LimitState
  └─ SortState
    └─ HashJoinState
      ├─ SeqScanState (employees)
      └─ HashState
        └─ SeqScanState (departments)
```

**ExecutorRun** executes the plan:

1. **Initialize Hash Table**:
   - SeqScan on departments with filter
   - Insert matching rows (location = 'New York') into hash table
   - Result: 5 rows in hash table

2. **Probe Phase**:
   - SeqScan on employees with filter (salary > 50000)
   - For each row, hash dept_id and probe hash table
   - Emit joined rows (~100 rows)

3. **Sort**:
   - Collect all joined rows
   - Sort by salary DESC
   - Result: 100 sorted rows

4. **Limit**:
   - Return first 10 rows
   - Stop execution

**Final Result** (10 tuples):
```
  name    | salary  | dept_name
----------+---------+-----------
 Alice    | 120000  | Engineering
 Bob      | 115000  | Engineering
 Charlie  | 110000  | Engineering
 ...
```

### 11.6 Performance Monitoring

**EXPLAIN ANALYZE output**:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT e.name, e.salary, d.dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE e.salary > 50000
  AND d.location = 'New York'
ORDER BY e.salary DESC
LIMIT 10;
```

**Output**:
```
Limit  (cost=224.05..230.69 rows=10 width=44)
       (actual time=5.234..5.248 rows=10 loops=1)
  Buffers: shared hit=115
  ->  Sort  (cost=224.05..230.64 rows=100 width=44)
            (actual time=5.232..5.234 rows=10 loops=1)
        Sort Key: e.salary DESC
        Sort Method: top-N heapsort  Memory: 26kB
        Buffers: shared hit=115
        ->  Hash Join  (cost=10.55..224.05 rows=100 width=44)
                      (actual time=0.087..4.892 rows=95 loops=1)
              Hash Cond: (e.dept_id = d.dept_id)
              Buffers: shared hit=115
              ->  Seq Scan on employees e  (cost=0.00..200.00 rows=5000 width=36)
                                          (actual time=0.012..3.456 rows=4987 loops=1)
                    Filter: (salary > 50000)
                    Rows Removed by Filter: 5013
                    Buffers: shared hit=100
              ->  Hash  (cost=10.50..10.50 rows=5 width=12)
                       (actual time=0.067..0.068 rows=5 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    Buffers: shared hit=15
                    ->  Seq Scan on departments d  (cost=0.00..10.50 rows=5 width=12)
                                                   (actual time=0.008..0.062 rows=5 loops=1)
                          Filter: (location = 'New York'::text)
                          Rows Removed by Filter: 45
                          Buffers: shared hit=15
Planning Time: 0.543 ms
Execution Time: 5.298 ms
```

---

## Conclusion

PostgreSQL's query processing pipeline represents a sophisticated implementation of decades of database research. The four-stage architecture—parsing, rewriting, planning, and execution—provides both flexibility and performance:

- **Parser** ensures SQL correctness and transforms text into structured data
- **Rewriter** applies views, rules, and security policies transparently
- **Planner** evaluates multiple execution strategies and selects the optimal one
- **Executor** efficiently generates result tuples using iterator-based processing

The cost-based optimizer, with its parameterized cost model and comprehensive path generation, enables PostgreSQL to handle complex queries efficiently across diverse workloads and data distributions.

Understanding this pipeline is essential for:
- **Query optimization**: Writing queries that can be optimized effectively
- **Performance tuning**: Adjusting cost parameters and creating appropriate indexes
- **Extension development**: Adding new operators, functions, or access methods
- **Troubleshooting**: Diagnosing query performance issues

The query processing system continues to evolve, with recent additions including parallel query execution, JIT compilation for expressions, and improved join algorithms, ensuring PostgreSQL remains competitive with modern database systems while maintaining its commitment to standards compliance and extensibility.
