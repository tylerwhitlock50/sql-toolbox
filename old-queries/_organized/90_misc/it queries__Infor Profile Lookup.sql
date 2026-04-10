-- Infor profile lookup, assignment of profiles, what ones are allowed, what ones have no access, etc. ----
use veca
select distinct user_id
from user_profile left outer join application_user on user_id = name
where
user_id not in (
    select user_id
    from user_profile
    where profile_id = 'NOACCESS'
)--and
--profile_id <> 'TOOLBAR'
and
edit_brwse_allowed = 'Y'


select profile_id, count(profile_id) as profile_total from user_profile
where
user_id not in (
    select user_id
    from user_profile
    where profile_id = 'NOACCESS'
)and
profile_id <> 'TOOLBAR'
group by profile_id


select distinct user_profile.user_id, vta.dbo.labor_employee.LSA_ID from user_profile left join vta.dbo.labor_employee on user_profile.user_id = vta.dbo.labor_employee.LSA_ID where user_id not in (
    select user_id
    from user_profile
    where profile_id = 'NOACCESS'
)and  profile_id <> 'TOOLBAR' and vta.dbo.labor_employee.status <> 'ACTIVE'


select * from user_profile where user_id = 'AMMONS'


select * from application_user where name = 'AMMONS'


select distinct user_id from USER_PROFILE inner join application_user on user_profile.user_ID = application_user.NAME where edit_brwse_allowed = 'Y'
select * from USER_FLD_AUTHORITY where user_id = 'ANDCHR'
select * from USER_MNU_AUTHORITY where user_id = 'PROD1'
select * from USER_PGM_AUTHORITY where user_id = 'PROD1' and PERMISSION <> 'N'