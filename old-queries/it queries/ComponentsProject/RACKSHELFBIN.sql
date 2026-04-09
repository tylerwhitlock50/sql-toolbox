-- Parameters
DECLARE @WarehouseId  nvarchar(50) = N'DISTRIBUTION';
DECLARE @Type         char(1) = 'R';

-- Per-rack config: how many shelves each rack has, and how many bins per shelf
DECLARE @RackConfig TABLE (
    Rack int      NOT NULL,
    Shelves int   NOT NULL,
    BinsPerShelf int NOT NULL
);

-- EXAMPLE CONFIG — edit these rows to match your layout
INSERT INTO @RackConfig (Rack, Shelves, BinsPerShelf) VALUES
(1, 3, 0),   -- Rack 1: 4 shelves, 4 bins each shelf
(2, 3, 0),   -- Rack 2: 4 shelves, 8 bins each shelf
(3, 3, 0),   -- Rack 3: 4 shelves, 8 bins each shelf
(4, 3, 0);
-- Build a tally (1..N) large enough for both shelves and bins
DECLARE @MaxShelves     int = (SELECT MAX(Shelves)     FROM @RackConfig);
DECLARE @MaxBinsPerShelf int = (SELECT MAX(BinsPerShelf) FROM @RackConfig);
DECLARE @MaxN int = (SELECT CASE WHEN @MaxShelves > @MaxBinsPerShelf THEN @MaxShelves ELSE @MaxBinsPerShelf END);

;WITH N AS (
    SELECT TOP (@MaxN) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects  -- lots of rows available
),
Shelves AS (
    SELECT rc.Rack, n.n AS Shelf
    FROM @RackConfig rc
    JOIN N n ON n.n <= rc.Shelves
),
Bins AS (
    SELECT rc.Rack, s.Shelf, n.n AS Bin
    FROM Shelves s
    JOIN @RackConfig rc ON rc.Rack = s.Rack
    JOIN N n ON n.n <= rc.BinsPerShelf
),
ToInsert AS (
    SELECT
        ID = 'STOCK-R' + RIGHT('0' + CAST(b.Rack  AS varchar(2)), 2) +
             'S' + RIGHT('0' + CAST(b.Shelf AS varchar(2)), 2) +
             'B' + RIGHT('0' + CAST(b.Bin   AS varchar(2)), 2),
        WAREHOUSE_ID = @WarehouseId,
        DESCRIPTION  = 'Rack ' + CAST(b.Rack AS varchar(10)) +
                       ' Shelf ' + CAST(b.Shelf AS varchar(10)) +
                       ' Bin ' + CAST(b.Bin AS varchar(10)) +
                       ', this was added via Query',
        TYPE = @Type,
        CUSTOMER_ID = CAST(NULL AS int),
        VENDOR_ID   = CAST(NULL AS int)
    FROM Bins b
)
INSERT INTO LOCATION (ID, WAREHOUSE_ID, DESCRIPTION, TYPE, CUSTOMER_ID, VENDOR_ID)
SELECT t.ID, t.WAREHOUSE_ID, t.DESCRIPTION, t.TYPE, t.CUSTOMER_ID, t.VENDOR_ID
FROM ToInsert t
WHERE NOT EXISTS (SELECT 1 FROM LOCATION L WHERE L.ID = t.ID);


INSERT INTO LOCATION (ID, WAREHOUSE_ID, DESCRIPTION, TYPE, CUSTOMER_ID, VENDOR_ID)
Values ('R01-OVERSTOCK','DISTRIBUTION','Rack 1 Overstock Location, add via Query ' + GETDATE(), 'R',CAST(NULL AS int), CAST(NULL AS int))