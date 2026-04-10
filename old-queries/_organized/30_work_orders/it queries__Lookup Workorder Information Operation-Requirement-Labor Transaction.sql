use veca
SELECT 'OP' AS TYPE, O.WORKORDER_BASE_ID, O.SEQUENCE_NO, O.RESOURCE_ID, O.STATUS, 0 AS PIECE_NO, 
                      O.CALC_START_QTY, O.COMPLETED_QTY, O.DEVIATED_QTY, '' AS DESCRIPTION, O.STATUS_EFF_DATE, CONVERT(NVARCHAR(MAX),CONVERT(VARBINARY(MAX), OB.BITS)) as LINE_SPECS 
                      FROM OPERATION O 
					  left join OPERATION_BINARY OB on O.WORKORDER_BASE_ID = OB.WORKORDER_BASE_ID
                      WHERE O.WORKORDER_BASE_ID='543455' 
                      UNION 
                      SELECT 'REQ' AS TYPE, R.WORKORDER_BASE_ID, R.OPERATION_SEQ_NO, R.PART_ID, R.STATUS, R.PIECE_NO, 
                      R.CALC_QTY, R.ISSUED_QTY, 0 AS DEVIATED_QTY, PART.DESCRIPTION, R.STATUS_EFF_DATE, '' 
                      FROM REQUIREMENT R 
                      INNER JOIN PART ON PART.ID=R.PART_ID 
                      WHERE R.WORKORDER_BASE_ID='543455' 
                      UNION 
                      SELECT 'PLT' AS TYPE, LT.WORKORDER_BASE_ID, LT.OPERATION_SEQ_NO, LT.RESOURCE_ID, '' AS STATUS, 
                      0 AS PIECE_NO, ISNULL(LT.HOURS_WORKED,0), LT.GOOD_QTY, LT.BAD_QTY, LT.EMPLOYEE_ID AS EMP_ID, 
                      LT.TRANSACTION_DATE, '' 
                      FROM LABOR_TICKET LT 
                      WHERE LT.WORKORDER_BASE_ID='543455' 
                      ORDER BY SEQUENCE_NO, PIECE_NO;

					  SELECT SEQUENCE_NO, CONVERT(NVARCHAR(MAX),CONVERT(VARBINARY(MAX), OB.BITS)) as LINE_SPECS
					  from OPERATION_BINARY OB 
                      WHERE WORKORDER_BASE_ID='543455' 

					  select * from work_order where part_id like 'RMA%' and create_date < '2024-01-01' order by create_date asc

					  select top 1 * from OPERATION