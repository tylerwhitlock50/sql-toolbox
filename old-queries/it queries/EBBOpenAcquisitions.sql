SELECT *
FROM  [TDJ Buyer LLC$Easy Bound Book$edafca1e-50f0-4968-9832-c717a8334d71]
 "TDJ Buyer LLC$Easy Bound Book"
WHERE (dispcompany='') AND (Corrected=0) 
ORDER BY acqdate desc

SELECT *
FROM "TEST_DB_CHRISTENSEN$Easy Bound Book$edafca1e-50f0-4968-9832-c717a8334d71" "TDJ Buyer LLC$Easy Bound Book"
WHERE ("TDJ Buyer LLC$Easy Bound Book".dispcompany='') AND ("TDJ Buyer LLC$Easy Bound Book".Corrected=0) 
ORDER BY acqdate desc

SELECT *
FROM "Christensen_Arms$Easy Bound Book" "TDJ Buyer LLC$Easy Bound Book"
WHERE ("TDJ Buyer LLC$Easy Bound Book".dispcompany='') AND ("TDJ Buyer LLC$Easy Bound Book".Corrected=0) 
ORDER BY acqdate desc