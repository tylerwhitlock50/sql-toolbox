SELECT 
 PART.ID,
 PART.DESCRIPTION, 
 PART.PRODUCT_CODE, 
 PART.COMMODITY_CODE, 
 PART.PURCHASED,
 chambering.chambering,
 Bar_Length.Bar_Length,
 twist.twist,
 family.family,
 finish.finish,
 handedness.handedness,
 action_type.action_type,
 handguard.handguard,
 stock_color.stock_color,
 stock_style.stock_style

FROM VECA.dbo.PART PART

 --add user defined fields   

--Chambering 
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as chambering
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000022') as Chambering 

on Chambering.DOCUMENT_ID = part.id

--barrel length
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as Bar_Length
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000025') as Bar_Length

on Bar_Length.DOCUMENT_ID = part.id

--Twist
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as Twist
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000024') as Twist

on Twist.DOCUMENT_ID = part.id

--Family
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as Family
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000021') as Family

on Family.DOCUMENT_ID = part.id

--finish
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as finish
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000030') as finish

on finish.DOCUMENT_ID = part.id

--handedness
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as handedness
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000031') as handedness

on handedness.DOCUMENT_ID = part.id

--action_type
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as action_type
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000036') as action_type

on action_type.DOCUMENT_ID = part.id

--handguard
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as handguard
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000032') as handguard

on handguard.DOCUMENT_ID = part.id

--Stock_color
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as stock_color
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000023') as stock_color

on stock_color.DOCUMENT_ID = part.id

--Stock_style
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as stock_style
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000029') as stock_style

on stock_style.DOCUMENT_ID = part.id

