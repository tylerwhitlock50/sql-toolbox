

/*=
This query will return all the parts that have stockout exceptions.

*/

SELECT ps.part_id as part_id_ps, ps.BUYER_USER_ID, ps.planner_user_id, ps.description, e.*
  FROM [VECA].[dbo].[TW_MRP_EXCEPTIONS] e join part_site_view ps on ps.part_id = e.part_id
  where e.stockout_qty > 0