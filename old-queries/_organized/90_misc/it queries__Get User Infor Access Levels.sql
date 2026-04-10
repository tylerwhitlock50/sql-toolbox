--------------------------
--Get Edit Browse Access
--------------------------
use veca
select distinct user_id
from user_profile left outer join application_user on user_id = name
where
user_id not in (    select user_id    from user_profile    where profile_id = 'NOACCESS'
)--and
--profile_id <> 'TOOLBAR'
and
edit_brwse_allowed = 'Y'

--------------------------
--Get total number of users assigned to profiles
--------------------------
select profile_id, count(profile_id) as profile_total from user_profile
where
user_id not in (    select user_id    from user_profile    where profile_id = 'NOACCESS'
)and
profile_id <> 'TOOLBAR'
group by profile_id


--------------------------
--Get users that still have VECA access but are terminated in VTA
--------------------------
select distinct user_profile.user_id, vta.dbo.labor_employee.LSA_ID from user_profile left join vta.dbo.labor_employee on user_profile.user_id = vta.dbo.labor_employee.LSA_ID where user_id not in (    select user_id    from user_profile    where profile_id = 'NOACCESS')and  profile_id <> 'TOOLBAR' and vta.dbo.labor_employee.status <> 'ACTIVE'

--------------------------
--Get user profile based on user id (ammon for example)
--------------------------
select * from user_profile where user_id = 'AMMONS'

--------------------------
--Get base user info from application_user table
--------------------------
select * from application_user where name = 'BRYTID'

--------------------------
--Another example of getting "edit browse", anyone who doesn't have "NOACCESS" (meaning they're terminated users)
--------------------------
select distinct user_id 
from USER_PROFILE inner join application_user 
on user_profile.user_ID = application_user.NAME 
where edit_brwse_allowed = 'Y' 
and user_id not in (    select user_id    from user_profile    where profile_id = 'NOACCESS')

--------------------------
--Get program field permissions by profile id
--------------------------
select * from USER_FLD_AUTHORITY where user_id = 'SC1'

--------------------------
--Get Menu permissions by profile_id
--------------------------
select * from USER_MNU_AUTHORITY where user_id = 'PROD1'

--------------------------
--Get program permissions based on profile_id
--------------------------
select * from USER_PGM_AUTHORITY where user_id = 'PROD1' and PERMISSION <> 'N'