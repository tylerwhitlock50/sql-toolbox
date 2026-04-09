DECLARE @PRTID varchar(50) = ''
DECLARE @TRCID varchar(50) = '7M2200056'
DECLARE @BASEID varchar(50) = ''


SELECT
    p.USER_6 AS UPC,
    pick.TRACE_ID AS SN,
    p.ID AS SKU,
    COALESCE(CONVERT(NVARCHAR(MAX), CONVERT(VARBINARY(MAX), pcb.BITS)), p.DESCRIPTION) AS LONG_DESC,
    udf.STRING_VAL AS PRODUCT
FROM (
    SELECT TOP 1 *
    FROM (
        -- Rule 1: Incoming Receipt (I/R)
        SELECT
            tit.TRACE_ID,
            it.TRANSACTION_ID,
            it.PART_ID AS TARGET_PART_ID,
            it.TRANSACTION_DATE AS event_time
        FROM TRACE_INV_TRANS tit
        JOIN INVENTORY_TRANS it
            ON it.TRANSACTION_ID = tit.TRANSACTION_ID
        WHERE tit.TRACE_ID = @TRCID
          AND it.TYPE = 'I'
          AND it.CLASS = 'R'

        UNION ALL

        -- Rule 2: Outgoing/Input (O/I) that builds into something via WORK_ORDER
        SELECT
            tit.TRACE_ID,
            it.TRANSACTION_ID,
            wo.PART_ID AS TARGET_PART_ID,
            it.CREATE_DATE AS event_time
        FROM TRACE_INV_TRANS tit
        JOIN INVENTORY_TRANS it
            ON it.TRANSACTION_ID = tit.TRANSACTION_ID
        JOIN WORK_ORDER wo
            ON wo.BASE_ID = it.WORKORDER_BASE_ID and wo.LOT_ID = it.WORKORDER_LOT_ID and wo.SPLIT_ID = it.WORKORDER_SPLIT_ID and wo.SUB_ID = it.WORKORDER_SUB_ID
        WHERE tit.TRACE_ID = @TRCID
          AND it.TYPE = 'O'
          AND it.CLASS = 'I'
    ) AS combined
    ORDER BY event_time DESC, TRANSACTION_ID DESC
) AS pick
JOIN PART p
    ON p.ID = pick.TARGET_PART_ID
LEFT JOIN PART_CO_BINARY pcb
    ON pcb.PART_ID = p.ID
LEFT JOIN USER_DEF_FIELDS udf
    ON udf.DOCUMENT_ID = p.ID
   AND udf.ID = 'UDF-0000021'
WHERE p.USER_6 IS NOT NULL;





SELECT * FROM INVENTORY_TRANS join TRACE_INV_TRANS on INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID where 
TRACE_ID = @TRCID and WORKORDER_BASE_ID = @BASEID

SELECT * FROM WORK_ORDER where BASE_ID = @BASEID

SELECT * FROM PART where ID = @PRTID

SELECT * FROM PART_SITE where PART_ID = @PRTID

