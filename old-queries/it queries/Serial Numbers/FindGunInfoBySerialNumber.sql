SELECT 
    inv.part_id AS Sku, 
	trace.TRACE_ID as Serial,
    MAX(CASE WHEN udf.ID = 'UDF-0000021' THEN udf.STRING_VAL ELSE NULL END) AS "Family",
    MAX(CASE WHEN udf.ID = 'UDF-0000023' THEN udf.STRING_VAL ELSE NULL END) AS "Stock Finish",
    MAX(CASE WHEN udf.ID = 'UDF-0000029' THEN udf.STRING_VAL ELSE NULL END) AS "Stock Style",
    MAX(CASE WHEN udf.ID = 'UDF-0000036' THEN udf.STRING_VAL ELSE NULL END) AS "Action Type",
    MAX(CASE WHEN udf.ID = 'UDF-0000022' THEN udf.STRING_VAL ELSE NULL END) AS "Chambering (Caliber)",
    MAX(CASE WHEN udf.ID = 'UDF-0000025' THEN udf.STRING_VAL ELSE NULL END) AS "Length",
    MAX(CASE WHEN udf.ID = 'UDF-0000024' THEN udf.STRING_VAL ELSE NULL END) AS "Rifling/Twist",
    MAX(CASE WHEN udf.ID = 'UDF-0000030' THEN udf.STRING_VAL ELSE NULL END) AS "Barrel Finish",
    MAX(CASE WHEN udf.ID = 'UDF-0000031' THEN udf.STRING_VAL ELSE NULL END) AS "Orientation",
    MAX(CASE WHEN udf.ID = 'UDF-0000032' THEN udf.STRING_VAL ELSE NULL END) AS "Handguard"
FROM inventory_trans inv
INNER JOIN trace_inv_trans trace 
    ON trace.transaction_id = inv.transaction_id
INNER JOIN USER_DEF_FIELDS udf 
    ON udf.document_id = inv.part_id
GROUP BY inv.part_id, trace.TRACE_ID