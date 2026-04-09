use veca
select w.base_id, w.create_date, sum(issued_qty) as issued_qty, sum(r.CALC_QTY) as calc_qty from work_order w  inner join requirement r on w.BASE_ID = r.WORKORDER_BASE_ID where w.status not in ('X', 'C') and w.type = 'W'
group by w.base_id, w.create_date
having sum(issued_qty) = 0
order by create_date asc