DROP TABLE IF EXISTS #AddrUPDATE
create table #AddrUpdate (
	ID NVARCHAR(50),
	ADDR_3 NVARCHAR(255),
	NEW_ADDR_3 NVARCHAR(255)
);
 
BULK INSERT #AddrUpdate
FROM '\\2CARMS\CARMS$\CA shared files\EDI\NBS ADDR Test Update.csv'
WITH (
    FIRSTROW = 2,              
    FIELDTERMINATOR = ',',     
    ROWTERMINATOR = '\n',  
    CODEPAGE = '65001',     
    TABLOCK
);

SELECT * FROM CUST_ADDRESS where CUSTOMER_ID in (select id from #AddrUpdate)
 
UPDATE ca
SET ca.addr_3 = u.NEW_ADDR_3
FROM test2.dbo.cust_address ca
INNER JOIN #AddrUpdate u
    ON ca.CUSTOMER_ID = u.id
WHERE u.NEW_ADDR_3 IS NOT NULL;


