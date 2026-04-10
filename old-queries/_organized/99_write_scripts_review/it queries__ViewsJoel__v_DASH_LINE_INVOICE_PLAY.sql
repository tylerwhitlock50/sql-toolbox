USE [EnTrust]
GO

/****** Object:  View [ESI_EDI].[v_DASH_LINE_INVOICE_PLAY]    Script Date: 9/8/2021 1:26:55 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [ESI_EDI].[v_DASH_LINE_INVOICE_PLAY] 
									AS
									SELECT NULL																			AS [ESI_DASH_LINE_ID]
										  ,NULL																			AS [ESI_DASH_HEADER_ID]
										  ,NULL																			AS [ESI_DASH_PACK_ID]
										  ,ERP_ORL.[LINE_NO]															AS [CUSTOMER_ORDER_LINE_NO]
										  ,NULL																			AS [EDI_ORDER_LINE_NO]
										  ,ERP_ORL.[LINE_STATUS]														AS [LINE_STATUS]
										  ,NULL																			AS [APPLICATION_ID]
										  ,ERP_ORL.[PART_ID]															AS [PART_ID]
										  ,ERP_ORL.[MISC_REFERENCE]														AS [PART_DESCRIPTION]
										  ,ERP_ORL.[CUSTOMER_PART_ID]													AS [BUYER_PART_NUMBER]
										  ,ERP_ORL.[MISC_REFERENCE]														AS [EDI_DESCRIPTION]
										  ,ERP_ORL.[PART_ID]															AS [VENDOR_PART_NUMBER]
										  ,NULL																			AS [CONSUMER_PKG_CODE]
										  ,NULL																			AS [EAN]
										  ,NULL																			AS [GTIN]
										  ,NULL																			AS [UPC_CASE_CODE]
										  ,NULL																			AS [NATL_DRUG_CODE]
										  ,NULL																			AS [ISBN]
										  ,ERP_ORL.[USER_ORDER_QTY]														AS [ORDER_QTY]
										  ,ERP_ORL.[SELLING_UM]															AS [ORDER_QTY_UM]
										  ,NULL																			AS [EDI_ORDER_QTY]
										  ,NULL																			AS [EDI_ORDER_QTY_UM]
										  ,ERP_SHL.[USER_SHIPPED_QTY]													AS [SHIP_QTY]
										  ,ERP_SHL.[SHIPPING_UM]														AS [SHIP_QTY_UM]
										  ,ERP_SHH.[SHIPPED_DATE]														AS [SHIP_DATE]
										  ,NULL																			AS [PURCHASE_PRICE_TYPE]
										  ,CASE WHEN ISNULL(ERP_ORL.[TRADE_DISC_PERCENT], '0.0') > 0
												THEN CAST((ISNULL(ERP_ORL.[UNIT_PRICE], '0.0') - (ISNULL(ERP_ORL.[UNIT_PRICE], '0.0') * (ERP_ORL.[TRADE_DISC_PERCENT] / 100))) AS DECIMAL(15, 6))
												ELSE CAST(ISNULL(ERP_ORL.[UNIT_PRICE], '0.0') AS DECIMAL(15, 6)) END	AS [PURCHASE_PRICE]	
										  ,ERP_ORL.[UNIT_PRICE]															AS [EDI_PURCHASE_PRICE]
										  ,CASE WHEN ERP_ORL.[SELLING_UM] = 'EA' THEN 'PE' -- per each
												WHEN ERP_ORL.[SELLING_UM] = 'LB' THEN 'PP' -- per pound
												ELSE  'CA' --Catalog 
												END																		AS [PURCHASE_PRICE_BASIS]
										  ,NULL																			AS [BUYERS_CURRENCY]
										  ,NULL																			AS [SELLERS_CURRENCY]
										  ,NULL																			AS [EXCHANGE_RATE]
										  ,ERP_ORL.[DESIRED_SHIP_DATE]													AS [DESIRED_SHIP_DATE]
										  ,ERP_ORL.[PROMISE_DEL_DATE]													AS [PROMISE_DEL_DATE]
										  ,ERP_ORL.[PROMISE_DATE]														AS [PROMISE_DATE]
										  ,ERP_RCL.[AMOUNT]																AS [EXTENDED_ITEM_TOTAL]
										  ,(ERP_ORL.[USER_ORDER_QTY] - ISNULL(ERP_ORL.[TOTAL_USR_SHIP_QTY], 0))			AS [QTY_LEFT_RECV]	
										  ,NULL																			AS [QTY_LEFT_RECV_STATUS]
										  ,NULL																			AS [PRODUCT_SIZE_CODE]
										  ,NULL																			AS [PRODUCT_SIZE_DESCRIPTION]
										  ,NULL																			AS [PRODUCT_COLOR_CODE]
										  ,NULL																			AS [PRODUCT_COLOR_DESCRIPTION]
										  ,NULL																			AS [PRODUCT_MATERIAL_CODE]
										  ,NULL																			AS [PRODUCT_MATERIAL_DESCRIPTION]
										  ,NULL																			AS [PRODUCT_PROCESS_CODE]
										  ,NULL																			AS [PRODUCT_PROCESS_DESCRIPTION]
										  ,NULL																			AS [DEPARTMENT]
										  ,NULL																			AS [DEPARTMENT_DESCRIPTION]
										  ,NULL																			AS [CLASS]
										  ,NULL																			AS [GENDER]
										  ,NULL																			AS [SELLER_DATE_CODE]
										  ,ERP_ORL.[EDI_RELEASE_NO]														AS [RELEASE_NO]
										  ,ERP_REC.[CREATE_DATE]														AS [ADD_DATE]
										  ,ERP_REC.[CREATE_DATE]														AS [CHANGE_DATE]
										  ,NULL																			AS [DELETE_DATE]
										  ,ERP_ORL.[GL_REVENUE_ACCT_ID]													AS [LINE_GL_ACCOUNT_ID]
										  ,TAX.[GL_ACCOUNT_ID]															AS [TAX_GL_ACCOUNT_ID]
										  ,ERP_ORH.[CUSTOMER_ID]														AS [ERP_CUSTOMER_ID]  
										  ,ERP_ORH.[CUSTOMER_PO_REF]													AS [PURCHASE_ORDER_NUMBER]
										  ,ERP_ORH.[ID]																	AS [CUSTOMER_ORDER_ID]
										  ,ERP_RCL.[PACKLIST_ID]														AS [SHIPMENT_ID]
										  ,ERP_RCL.[INVOICE_ID]															AS [INVOICE_ID]
										  ,ERP_ORH.[SITE_ID]															AS [SITE_ID]
										  ,NULL																			AS [PLANT_ID]
										  ,ERP_ORL.[WAREHOUSE_ID]														AS [WAREHOUSE_ID]
									FROM [6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE_LINE] ERP_RCL
										INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE] ERP_REC 
											ON ERP_REC.[INVOICE_ID]	= ERP_RCL.[INVOICE_ID]	
										LEFT JOIN [6CARMS\CAPROD].[VECA].[dbo].[SHIPPER_LINE] ERP_SHL 
											ON ERP_SHL.[PACKLIST_ID] = ERP_RCL.[PACKLIST_ID]
											AND ERP_SHL.[LINE_NO] = ERP_RCL.[PACKLIST_LINE_NO]	
										LEFT JOIN [6CARMS\CAPROD].[VECA].[dbo].[SHIPPER] ERP_SHH	
											ON ERP_SHH.[PACKLIST_ID] = ERP_SHL.[PACKLIST_ID]
										INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[CUSTOMER_ORDER] ERP_ORH 
											ON ERP_ORH.[ID] = ERP_SHH.[CUST_ORDER_ID] 
										INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[CUST_ORDER_LINE] ERP_ORL	
											ON ERP_ORL.[CUST_ORDER_ID] = ERP_SHL.[CUST_ORDER_ID]
											AND ERP_ORL.[LINE_NO] = ERP_SHL.[CUST_ORDER_LINE_NO]
										INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[PART] ERP_PRT 
											ON ERP_PRT.[ID]	= ERP_ORL.[PART_ID]	
										INNER JOIN [6CARMS\CAPROD].[VECA].[dbo].[SITE] SIT     
											ON SIT.[ID] = ERP_ORH.[SITE_ID]
										LEFT JOIN [6CARMS\CAPROD].[VECA].[dbo].[SALES_TAX] TAX	
											ON TAX.[GL_ACCOUNT_ID] = ERP_ORL.[GL_REVENUE_ACCT_ID]
GO


