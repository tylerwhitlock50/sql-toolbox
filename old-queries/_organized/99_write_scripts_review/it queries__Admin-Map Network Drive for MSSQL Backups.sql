USE [MASTER]
GO

CREATE PROC [dbo].[usp_DBA_Enable_Network_Backup_Drive]

AS

-- Use xp_cmdshell extended stored procedure to map network drive from inside of MSSQL --
--NOTE: Put password in the {pwd} spot, don't save it locally
EXEC xp_cmdshell 'net use B: \\stor\bak\Backups\SQL\EBB {pwd} /USER:CARMS\administrator /persistent:yes /y'

GO

EXEC sp_procoption N'[dbo].[usp_DBA_Enable_Network_Backup_Drive]', 'startup', '1'

GO