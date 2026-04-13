select * from cu

se
id,
customer_id,
customer_po_ref
ship_to_addr_no,
territory,
salesrep_id,
terms_net_type,
terms_net_days,
terms_disc_type,
terms_disc_date,
Terms_disc_percent, -- total discount i.e.
terms_description, --human readable terms
order_date, -- The date the order was placed
desired_ship_date, -- this is the order date when ERP expects the order to ship
back_order,
status, -- order status c=closed normally (fully shipped), x=cancelled, R= released (ready to ship when date comes), F=firmed but not okay to ship, U= unreleased 
posting_candidate, --somthing has not posted for accounting