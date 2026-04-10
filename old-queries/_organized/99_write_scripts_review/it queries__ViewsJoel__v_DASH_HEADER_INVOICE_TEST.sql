USE [EnTrust]
GO

/****** Object:  View [ESI_EDI].[v_DASH_HEADER_INVOICE_TEST]    Script Date: 9/8/2021 1:29:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [ESI_EDI].[v_DASH_HEADER_INVOICE_TEST]
									AS
									SELECT NULL													AS [DASH_HEADER_INVOICE_ID]
										  ,ERP_INH.[INVOICE_ID]									AS [INVOICE_ID]
										  ,NULL													AS [VOUCHER_ID]
										  ,ERP_INH.[INVOICE_DATE]								AS [INVOICE_DATE]
										  ,NULL													AS [SHIP_DELIVERY_DATE]
										  ,ERP_INH.[TOTAL_AMOUNT]								AS [INVOICE_TOTAL]
										  ,ERP_TAX.[TAX_AMOUNT]									AS [TOTAL_SALES_TAX]
										  ,NULL													AS [CONSOLIDATED_INVOICE_NUMBER]
										  ,NULL													AS [ESI_DASH_HEADER_ID]
										  ,NULL													AS [ESI_FILE_ID]
										  ,NULL													AS [EDI_STATUS]
										  ,EDI_TP.[TRADING_PARTNER_NAME]						AS [TRADING_PARTNER_NAME]
										  ,EDI_CST.[ESI_CUSTOMER_ID]							AS [ESI_CUSTOMER_ID]
										  ,ERP_ORH.[CUSTOMER_ID]								AS [ERP_CUSTOMER_ID]
										  ,EDI_GRP.[CUSTOMER_GROUP]								AS [CUSTOMER_GROUP]
										  ,ERP_ORH.[ID]											AS [CUSTOMER_ORDER_ID]
										  ,ERP_ORH.[CUSTOMER_PO_REF]							AS [PURCHASE_ORDER_NUMBER]
										  ,EDI_CST.[SITE_ID]									AS [SITE_ID]
										  ,NULL													AS [PLANT_ID]
										  ,ERP_ORH.[ORDER_DATE]									AS [ORDER_DATE]
										  ,ERP_ORH.[DESIRED_SHIP_DATE]							AS [DESIRED_SHIP_DATE]
										  ,ERP_ORH.[PROMISE_DEL_DATE]							AS [PROMISE_DEL_DATE]
										  ,ERP_ORH.[PROMISE_DATE]								AS [PROMISE_DATE]
										  ,ERP_ORH.[SHIPTO_ID]									AS [SHIPTO_ID]
										  ,CASE WHEN ISNULL(ERP_SHH.[SHIP_VIA], '') = ''
												THEN ERP_ORH.[SHIP_VIA]
												ELSE ERP_SHH.[SHIP_VIA] END						AS [SHIP_VIA]
										  ,ERP_ORH.[STATUS]										AS [ORDER_STATUS]
										  ,NULL													AS [DEPOSITOR_ORDER_NUMBER]
										  ,NULL													AS [TSETPURPOSECODE]
										  ,NULL													AS [PURCHASE_ORDER_TYPE_CODE]
										  ,NULL													AS [PURCHASE_ORDER_TYPE_DESCRIPTION]										  
										  ,ERP_ORH.[EDI_RELEASE_NO]								AS [EDI_RELEASE_NO]
										  ,ERP_ORH.[ORDER_DATE]									AS [PURCHASE_ORDER_DATE]
										  ,NULL													AS [CONTRACT_TYPE_CODE]
										  ,ERP_ORH.[CONTRACT_ID]								AS [CONTRACT_ID]
										  ,NULL													AS [SALES_REQUIREMENT_CODE]
										  ,NULL													AS [ACKNOWLEDGEMENT_TYPE]
										  ,ERP_INH.[TYPE]										AS [INVOICE_TYPE_CODE]
										  ,NULL													AS [SHIP_COMPLETE_CODE]
										  ,ERP_INH.[CURRENCY_ID]								AS [BUYERS_CURRENCY]
										  ,CASE WHEN ISNULL(ERP_INH.[CURRENCY_ID], '') = ''
												THEN EDI_GLB.[CURRENCY_ID]
												ELSE ERP_INH.[CURRENCY_ID] END					AS [SELLERS_CURRENCY]
										  ,ERP_INH.[SELL_RATE]									AS [EXCHANGE_RATE]
										  ,NULL													AS [DEPARTMENT]
										  ,NULL													AS [DEPARTMENT_DESCRIPTION]
										  ,EDI_CST.[VENDOR_ID]									AS [VENDOR_NUMBER]
										  ,NULL													AS [JOB_NUMBER]
										  ,NULL													AS [DIVISION]
										  ,NULL													AS [CUSTOMER_ACCOUNT_NUMBER]
										  ,NULL													AS [CUSTOMER_ORDER_NUMBER]
										  ,NULL													AS [PROMOTION_DEAL_NUMBER]
										  ,NULL													AS [PROMOTION_DEAL_DESCRIPTION]
										  ,NULL													AS [DOCUMENT_VERSION]
										  ,NULL													AS [DOCUMENT_REVISION]
										  ,NULL													AS [PURCHASE_CATEGORY]
										  ,NULL													AS [SECURITY_LEVEL_CODE]
										  ,NULL													AS [TRANSACTION_TYPE_CODE]	
										  ,NULL													AS [REFERENCE_IDENTIFICATION]	
										  ,NULL													AS [SCHEDULE_TYPE_QUALIFIER]
										  ,NULL													AS [SCHEDULE_QUANTITY_QUALIFER]
										  ,NULL													AS [HORIZON_START_DATE]	
										  ,NULL													AS [HORIZON_END_DATE]	
										  ,NULL													AS [GENERATED_DATE]	
										  ,NULL													AS [RECONCILIATION_DATE]	
										  ,NULL													AS [PLANNING_SCHEDULE_TYPE_CODE]
										  ,NULL													AS [ACTION_CODE]
										  ,NULL													AS [DOCUMENT_TYPE]
										  ,NULL													AS [EDI_DIRECTION]
										  ,ERP_INH.[CREATE_DATE]								AS [ADD_DATE]
										  ,NULL													AS [CHANGE_DATE]
										  ,NULL													AS [DELETE_DATE]
										  ,ERP_SHH.[PACKLIST_ID]								AS [SHIPMENT_ID]
										  ,NULL													AS [WAREHOUSE_ID]
									FROM [6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE] ERP_INH
										INNER JOIN [ESI_CORE].[ESI_CUSTOMER] EDI_CST 
											ON EDI_CST.[ERP_CUSTOMER_ID] = ERP_INH.[CUSTOMER_ID]
											AND EDI_CST.[SITE_ID] = ERP_INH.[SITE_ID]
											AND EDI_CST.[ENTRUST_ENABLED] = '1'
											AND EDI_CST.[DELETE_DATE] IS NULL
											AND EDI_CST.[CUSTOMER_TYPE] = 'C'
										INNER JOIN [ESI_CORE].[ESI_TRADING_PARTNER] EDI_TP  
											ON EDI_TP.[ESI_TRADING_PARTNER_ID] = EDI_CST.[ESI_TRADING_PARTNER_ID]
											AND EDI_TP.[DELETE_DATE] IS NULL
										LEFT JOIN [ESI_CORE].[ESI_CUSTOMER_GROUP] EDI_GRP 
											ON EDI_GRP.[ESI_CUSTOMER_GROUP_ID] = EDI_CST.[ESI_CUSTOMER_GROUP_ID]
											AND EDI_GRP.[IS_ENABLED] = '1'
											AND EDI_GRP.[DELETE_DATE] IS NULL
										LEFT JOIN [6CARMS\CAPROD].[VECA].[dbo].[SHIPPER] ERP_SHH 
											ON ERP_SHH.[INVOICE_ID] = ERP_INH.[INVOICE_ID]
										INNER JOIN  [6CARMS\CAPROD].[VECA].[dbo].[CUSTOMER_ORDER] ERP_ORH 
											ON ERP_ORH.[ID]	= ERP_SHH.[CUST_ORDER_ID]
										LEFT JOIN (SELECT RCV_LIN.[INVOICE_ID]  AS [INVOICE_ID]
														 ,SUM(RCV_LIN.[AMOUNT]) AS [TAX_AMOUNT]
												   FROM [6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE_LINE] RCV_LIN 
													   INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[SALES_TAX] TAX				
														    ON TAX.[GL_ACCOUNT_ID] = RCV_LIN.[GL_ACCOUNT_ID]
												   GROUP BY RCV_LIN.[INVOICE_ID]) AS ERP_TAX
											ON ERP_TAX.[INVOICE_ID] = ERP_INH.[INVOICE_ID]
										INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[SITE]	SIT     
											ON SIT.[ID] = ERP_ORH.[SITE_ID]
										OUTER APPLY	[ESI_CORE].[ESI_GLOBAL] EDI_GLB
GO


