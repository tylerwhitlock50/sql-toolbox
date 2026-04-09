use VFIN
EXEC sp_adduser 'KIRDOY'; -- Adds user to the DB if not already existing, usually with VFIN this is the case.

GRANT SELECT ON DATABASE :: VFIN TO KIRDOY
