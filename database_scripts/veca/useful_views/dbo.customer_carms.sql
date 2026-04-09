USE [VECA]
GO

/****** Object:  View [dbo].[CUSTOMER_CARMS]    Script Date: 4/9/2026 9:51:50 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[CUSTOMER_CARMS]
AS
SELECT        ID, CASE WHEN CUSTOMER.NAME LIKE '%SPORT%MAN%WARE%HOUSE%' OR
                         CUSTOMER.NAME LIKE '%PACIFIC%FLYWAY%WHOL%' OR
                         CUSTOMER.NAME LIKE '%SCHEEL%' OR
                         CUSTOMER.NAME LIKE '%CABELA%' OR
                         CUSTOMER.NAME LIKE '%BASS%PRO%' OR
                         CUSTOMER.ID = 'EURO OPTI' THEN 'BIG BOX' WHEN CUSTOMER.NAME LIKE '%LIPSEY%' OR
                         CUSTOMER.ID IN ('DAVIDS', 'ZANDERS', 'BILL HICK', 'RSR GROU', 'SPOR SOU1', 'IRON VALL', 'BROW INC', 'MGE WHOL', 'MIDW USA') OR
                         CUSTOMER.NAME LIKE '%ACUSPORT%' OR
                         CUSTOMER.NAME LIKE '%CHATTANOOGA%' THEN 'DISTRIBUTION' WHEN CUSTOMER.ADDR_3 LIKE '%NBS%' OR
                         CUSTOMER.DEF_RECV_ACCT_ID IN ('1202', '1204', '1206', '1208') OR
                         CUSTOMER.ADDR_3 LIKE '%SPORT%INC%' OR
                         CUSTOMER.ADDR_3 LIKE '%WORLD%WIDE%' OR
                         CUSTOMER.ADDR_3 LIKE '%WW%' OR
                         CUSTOMER.ADDR_3 LIKE '%MID%' THEN 'BUY GROUP' ELSE 'EVERYTHING ELSE' END AS CUSTOMER_GROUP, CASE WHEN CUSTOMER.NAME LIKE '%SPORT%MAN%WARE%HOUSE%' OR
                         CUSTOMER.NAME LIKE '%PACIFIC%FLYWAY%WHOL%' OR
                         CUSTOMER.NAME LIKE '%SCHEEL%' OR
                         CUSTOMER.NAME LIKE '%CABELA%' OR
                         CUSTOMER.NAME LIKE '%BASS%PRO%' OR
                         CUSTOMER.ID = 'EURO OPTI' THEN 'BIG BOX' WHEN CUSTOMER.NAME LIKE '%LIPSEY%' OR
                         CUSTOMER.ID IN ('DAVIDS', 'ZANDERS', 'BILL HICK', 'RSR GROU', 'SPOR SOU1', 'IRON VALL', 'BROW INC', 'MGE WHOL', 'MIDW USA') OR
                         CUSTOMER.NAME LIKE '%ACUSPORT%' OR
                         CUSTOMER.NAME LIKE '%CHATTANOOGA%' THEN 'DISTRIBUTION' WHEN CUSTOMER.ADDR_3 LIKE '%NBS%' THEN 'NBS' WHEN CUSTOMER.ADDR_3 LIKE '%SPORT%INC%' THEN 'SPORTS INC' WHEN CUSTOMER.ADDR_3 LIKE
                          '%WW%' THEN 'WORLDWIDE' WHEN CUSTOMER.ADDR_3 LIKE '%WORLD%WIDE%' THEN 'WORLDWIDE' WHEN CUSTOMER.ADDR_3 LIKE '%MID%STATE%' THEN 'MID STATES' WHEN CUSTOMER.DEF_RECV_ACCT_ID IN ('1202',
                          '1204', '1206', '1208') 
                         THEN CASE CUSTOMER.DEF_RECV_ACCT_ID WHEN '1202' THEN 'NBS' WHEN '1204' THEN 'SPORTS INC' WHEN '1206' THEN 'WORLDWIDE' WHEN '1208' THEN 'MID STATES' END ELSE 'EVERYTHING ELSE' END AS CUSTOMER_SUB_GROUP,
                          CASE WHEN CUSTOMER.NAME LIKE '%Chattanooga Shooting Supplies%' THEN 'Chattanooga Shooting Supplies' WHEN CUSTOMER.NAME LIKE '%Lipsey%' THEN 'LIPSEY''S LLC' WHEN CUSTOMER.NAME LIKE '%SPORT%MAN%WARE%HOUSE%'
                          OR
                         CUSTOMER.NAME LIKE '%PACIFIC%FLYWAY%WHOLE%' THEN 'SPORTSMANS WAREHOUSE' WHEN CUSTOMER.NAME LIKE '%SCHEEL%' THEN 'SCHEELS' WHEN CUSTOMER.NAME LIKE '%CABELA%' OR
                         CUSTOMER.NAME LIKE 'BASS%PRO%' THEN 'BP/CAB' WHEN CUSTOMER.NAME LIKE '%MURDOCHS%' THEN 'MURDOCHS' ELSE CUSTOMER.NAME END AS CUSTOMER_NAME
FROM            dbo.CUSTOMER
GO

EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPane1', @value=N'[0E232FF0-B466-11cf-A24F-00AA00A3EFFF, 1.00]
Begin DesignProperties = 
   Begin PaneConfigurations = 
      Begin PaneConfiguration = 0
         NumPanes = 4
         Configuration = "(H (1[16] 4[16] 2[49] 3) )"
      End
      Begin PaneConfiguration = 1
         NumPanes = 3
         Configuration = "(H (1 [50] 4 [25] 3))"
      End
      Begin PaneConfiguration = 2
         NumPanes = 3
         Configuration = "(H (1 [50] 2 [25] 3))"
      End
      Begin PaneConfiguration = 3
         NumPanes = 3
         Configuration = "(H (4 [30] 2 [40] 3))"
      End
      Begin PaneConfiguration = 4
         NumPanes = 2
         Configuration = "(H (1 [56] 3))"
      End
      Begin PaneConfiguration = 5
         NumPanes = 2
         Configuration = "(H (2 [66] 3))"
      End
      Begin PaneConfiguration = 6
         NumPanes = 2
         Configuration = "(H (4 [50] 3))"
      End
      Begin PaneConfiguration = 7
         NumPanes = 1
         Configuration = "(V (3))"
      End
      Begin PaneConfiguration = 8
         NumPanes = 3
         Configuration = "(H (1[56] 4[18] 2) )"
      End
      Begin PaneConfiguration = 9
         NumPanes = 2
         Configuration = "(H (1 [75] 4))"
      End
      Begin PaneConfiguration = 10
         NumPanes = 2
         Configuration = "(H (1[66] 2) )"
      End
      Begin PaneConfiguration = 11
         NumPanes = 2
         Configuration = "(H (4 [60] 2))"
      End
      Begin PaneConfiguration = 12
         NumPanes = 1
         Configuration = "(H (1) )"
      End
      Begin PaneConfiguration = 13
         NumPanes = 1
         Configuration = "(V (4))"
      End
      Begin PaneConfiguration = 14
         NumPanes = 1
         Configuration = "(V (2))"
      End
      ActivePaneConfig = 0
   End
   Begin DiagramPane = 
      Begin Origin = 
         Top = -96
         Left = -1751
      End
      Begin Tables = 
         Begin Table = "CUSTOMER"
            Begin Extent = 
               Top = 6
               Left = 38
               Bottom = 205
               Right = 370
            End
            DisplayFlags = 280
            TopColumn = 0
         End
      End
   End
   Begin SQLPane = 
   End
   Begin DataPane = 
      Begin ParameterDefaults = ""
      End
   End
   Begin CriteriaPane = 
      Begin ColumnWidths = 11
         Column = 1440
         Alias = 900
         Table = 1170
         Output = 720
         Append = 1400
         NewValue = 1170
         SortType = 1350
         SortOrder = 1410
         GroupBy = 1350
         Filter = 1350
         Or = 1350
         Or = 1350
         Or = 1350
      End
   End
End
' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'CUSTOMER_CARMS'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPaneCount', @value=1 , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'CUSTOMER_CARMS'
GO

