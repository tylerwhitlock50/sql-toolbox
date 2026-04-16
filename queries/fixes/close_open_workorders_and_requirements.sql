/*
Purpose
-------
This script closes old open requirement records and then closes old work orders
that no longer have any open requirements tied to them.

Business logic
--------------
1. Find requirement records for work-order-type jobs ('W') with required dates
   before 2025-01-01 that are still open.
2. Close those requirement records by setting status = 'C'.
3. Find work orders created before 2025-01-01 that are still open and now have
   no remaining open requirements.
4. Close those eligible work orders by setting status = 'C'.
5. Report any remaining open work orders that still have open requirements.

Important assumptions
---------------------
- 'C' = Closed
- 'X' = Cancelled
- Any status NOT IN ('X','C') is treated as still open
- Requirement-to-work-order linkage is based on:
    base_id / lot_id / split_id / sub_id
- This script is intended for reviewable cleanup of older records

Recommended usage
-----------------
1. Run first with ROLLBACK TRANSACTION
2. Review counts and detail list
3. If results look correct, rerun with COMMIT TRANSACTION
*/

BEGIN TRANSACTION;

------------------------------------------------------------
-- Step 1: Count old open requirements before update
--
-- This gives a baseline count of requirement rows that meet
-- the cleanup criteria and are expected to be closed.
------------------------------------------------------------
SELECT COUNT(*) AS req_before
FROM requirement
WHERE workorder_type = 'W'
  AND status NOT IN ('X', 'C')
  AND required_date < '2025-01-01';

------------------------------------------------------------
-- Step 2: Close old open requirements
--
-- Any requirement tied to a work-order-type record ('W'),
-- still open, and required before 2025-01-01 is set to closed.
------------------------------------------------------------
UPDATE r
SET r.status = 'C'
FROM requirement r
WHERE r.workorder_type = 'W'
  AND r.status NOT IN ('X', 'C')
  AND r.required_date < '2025-01-01';

------------------------------------------------------------
-- Step 3: Validate requirement cleanup
--
-- After the update, this count should ideally be 0.
-- If not, some rows were not updated as expected.
------------------------------------------------------------
SELECT COUNT(*) AS req_after
FROM requirement
WHERE workorder_type = 'W'
  AND status NOT IN ('X', 'C')
  AND required_date < '2025-01-01';

------------------------------------------------------------
-- Step 4: Count work orders eligible to close
--
-- A work order is eligible if:
--   - type = 'W'
--   - it is still open
--   - it was created before 2025-01-01
--   - it has NO remaining open requirements
--
-- NOT EXISTS is used here to ensure the work order only
-- closes when all linked requirements are no longer open.
------------------------------------------------------------
SELECT COUNT(*) AS wo_before
FROM work_order wo
WHERE wo.type = 'W'
  AND wo.status NOT IN ('X', 'C')
  AND wo.create_date < '2025-01-01'
  AND NOT EXISTS (
      SELECT 1
      FROM requirement r
      WHERE r.workorder_base_id  = wo.base_id
        AND r.workorder_lot_id   = wo.lot_id
        AND r.workorder_split_id = wo.split_id
        AND r.workorder_sub_id   = wo.sub_id
        AND r.status NOT IN ('X', 'C')
  );

------------------------------------------------------------
-- Step 5: Close eligible work orders
--
-- This closes only work orders that have no remaining open
-- requirement rows tied to them.
------------------------------------------------------------
UPDATE wo
SET wo.status = 'C'
FROM work_order wo
WHERE wo.type = 'W'
  AND wo.status NOT IN ('X', 'C')
  AND wo.create_date < '2025-01-01'
  AND NOT EXISTS (
      SELECT 1
      FROM requirement r
      WHERE r.workorder_base_id  = wo.base_id
        AND r.workorder_lot_id   = wo.lot_id
        AND r.workorder_split_id = wo.split_id
        AND r.workorder_sub_id   = wo.sub_id
        AND r.status NOT IN ('X', 'C')
  );

------------------------------------------------------------
-- Step 6: Validate work-order cleanup
--
-- After the update, this should ideally be 0 for the group
-- of work orders that were eligible to close.
------------------------------------------------------------
SELECT COUNT(*) AS wo_after
FROM work_order wo
WHERE wo.type = 'W'
  AND wo.status NOT IN ('X', 'C')
  AND wo.create_date < '2025-01-01'
  AND NOT EXISTS (
      SELECT 1
      FROM requirement r
      WHERE r.workorder_base_id  = wo.base_id
        AND r.workorder_lot_id   = wo.lot_id
        AND r.workorder_split_id = wo.split_id
        AND r.workorder_sub_id   = wo.sub_id
        AND r.status NOT IN ('X', 'C')
  );

------------------------------------------------------------
-- Step 7: Count work orders that remain open because they
-- still have at least one open requirement
--
-- This is an exception count, not a failure count.
-- These records were intentionally left open.
------------------------------------------------------------
SELECT COUNT(*) AS wo_still_open_with_open_requirements
FROM work_order wo
WHERE wo.type = 'W'
  AND wo.status NOT IN ('X', 'C')
  AND wo.create_date < '2025-01-01'
  AND EXISTS (
      SELECT 1
      FROM requirement r
      WHERE r.workorder_base_id  = wo.base_id
        AND r.workorder_lot_id   = wo.lot_id
        AND r.workorder_split_id = wo.split_id
        AND r.workorder_sub_id   = wo.sub_id
        AND r.status NOT IN ('X', 'C')
  );

------------------------------------------------------------
-- Step 8: Detail list of remaining open work orders that
-- still have open requirements
--
-- This is the inspection list for manual review.
------------------------------------------------------------
SELECT 
    wo.base_id,
    wo.lot_id,
    wo.split_id,
    wo.sub_id,
    wo.status,
    wo.create_date
FROM work_order wo
WHERE wo.type = 'W'
  AND wo.status NOT IN ('X', 'C')
  AND wo.create_date < '2025-01-01'
  AND EXISTS (
      SELECT 1
      FROM requirement r
      WHERE r.workorder_base_id  = wo.base_id
        AND r.workorder_lot_id   = wo.lot_id
        AND r.workorder_split_id = wo.split_id
        AND r.workorder_sub_id   = wo.sub_id
        AND r.status NOT IN ('X', 'C')
  )
ORDER BY wo.base_id, wo.lot_id, wo.split_id, wo.sub_id;

------------------------------------------------------------
-- Final step
--
-- Use ROLLBACK during testing.
-- Use COMMIT only after validating results.
------------------------------------------------------------

ROLLBACK TRANSACTION;
COMMIT TRANSACTION;