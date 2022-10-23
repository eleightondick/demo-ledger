IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 16
	RAISERROR('This script requires SQL Server 2022 or higher', 20, 1) WITH LOG;
IF @@ERROR <> 0
	SET NOEXEC ON;

USE [temporalDemo];

-- Let's see what widgets we're making
-- This table uses a trigger to update the rows
SELECT *
	FROM dbo.widget
	ORDER BY productId, changeDate;
SELECT *
	FROM dbo.widgetPriceHistory
	ORDER BY productId, changeDate;

-- Increase the prices
UPDATE dbo.widget
	SET price = price + ROUND((price * 0.05), 2),
		changeDate = GETDATE()
	WHERE price > 1.00;
SELECT *
	FROM dbo.widget
	ORDER BY productId, changeDate;
SELECT *
	FROM dbo.widgetPriceHistory
	ORDER BY productId, changeDate;
-- This works OK, but can it be easier?

-- Create a test temporal table and populate it
CREATE TABLE dbo.myTemporalTable (
	[productId] INT NOT NULL PRIMARY KEY,
	[name] VARCHAR(25) NOT NULL,
	[price] MONEY NOT NULL DEFAULT(0),
	[validFrom] DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
	[validTo] DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
	PERIOD FOR SYSTEM_TIME (validFrom, validTo))
	WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.myTemporalTable_History));
INSERT INTO myTemporalTable (productId, name, price)
	SELECT productId, name, price
		FROM dbo.widget;
SELECT *
	FROM dbo.myTemporalTable;
SELECT *
	FROM dbo.myTemporalTable_History;

-- Update the prices as before
UPDATE dbo.myTemporalTable
	SET price = price + ROUND((price * 0.05), 2)
	WHERE price > 1.00;
SELECT *
	FROM dbo.myTemporalTable;
SELECT *
	FROM dbo.myTemporalTable_History;

-- We can convert it in place, too!
-- This lets us preserve the history
DROP TRIGGER IF EXISTS dbo.trgUpdateWidgetHistory;
ALTER TABLE dbo.widget
	ALTER COLUMN changeDate DATETIME2 NOT NULL;
ALTER TABLE dbo.widget
	ADD [validTo] DATETIME2 NULL;
ALTER TABLE dbo.widgetPriceHistory
	DROP CONSTRAINT PK_widgetPriceHistory;						-- Primary keys aren't allowed on the history table
ALTER TABLE dbo.widgetPriceHistory
	ALTER COLUMN changeDate DATETIME2 NOT NULL;
ALTER TABLE dbo.widgetPriceHistory
	ADD [validTo] DATETIME2 NULL;

UPDATE dbo.widget
	SET validTo = '9999-12-31 23:59:59.9999999'
	WHERE validTo IS NULL;
WITH allRows AS
	(SELECT productId, name, price, changeDate
		FROM dbo.widget
	 UNION ALL
     SELECT productId, name, price, changeDate
		FROM dbo.widgetPriceHistory),
	allRowsWithValidTo AS
	(SELECT productId, name, price, changeDate, LEAD(changeDate, 1, '9999-12-31 23:59:59.9999999') OVER (PARTITION BY r.productId ORDER BY r.changeDate) AS validTo
		FROM allRows r)
UPDATE dbo.widgetPriceHistory
	SET validTo = n.validTo
	FROM dbo.widgetPriceHistory w
		INNER JOIN allRowsWithValidTo n ON n.productId = w.productId AND n.changeDate = w.changeDate AND n.validTo < '12/31/9999'
	WHERE w.validTo IS NULL;

ALTER TABLE dbo.widget
	ALTER COLUMN validTo DATETIME2 NOT NULL;					-- Period columns must not be nullable
ALTER TABLE dbo.widgetPriceHistory
	ALTER COLUMN validTo DATETIME2 NOT NULL;

ALTER TABLE dbo.widget
	ADD PERIOD FOR SYSTEM_TIME (changeDate, validTo);			-- SQL adds the GENERATE ALWAYS constraints automatically
ALTER TABLE dbo.widget
	SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.widgetPriceHistory, DATA_CONSISTENCY_CHECK = on));

SELECT *
	FROM dbo.widget
	ORDER BY productId, changeDate;
SELECT *
	FROM dbo.widgetPriceHistory
	ORDER BY productId, changeDate;

SELECT *
	FROM dbo.widget
	FOR SYSTEM_TIME AS OF '7/1/2022'
	ORDER BY productId, changeDate;

SELECT *
	FROM dbo.widget
	FOR SYSTEM_TIME AS OF '9/22/2022'
	ORDER BY productId, changeDate;

SELECT *
	FROM dbo.widget
	FOR SYSTEM_TIME FROM '9/1/2022' TO '9/30/2022'
	ORDER BY productId, changeDate;

SELECT *
	FROM dbo.widget
	FOR SYSTEM_TIME CONTAINED IN ('10/1/2022', '10/31/2022')
	ORDER BY productId, changeDate;

-- PROBLEM: Temporal table data can be modified!
UPDATE dbo.widget
	SET name = 'cheese',
		price = 9.00
	WHERE name = 'grommet';

SELECT *
	FROM dbo.widget
UNION ALL
SELECT *
	FROM dbo.widgetPriceHistory
ORDER BY productId, changeDate;

UPDATE dbo.widget
	SET name = 'grommet',
		price = 0.90
	WHERE name = 'cheese';

SELECT *
	FROM dbo.widget
UNION ALL
SELECT *
	FROM dbo.widgetPriceHistory
ORDER BY productId, changeDate;

ALTER TABLE dbo.widget
	SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE dbo.widget
	DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE dbo.widgetPriceHistory
	ALTER COLUMN changeDate DATETIME2 NOT NULL;

UPDATE dbo.widget
	SET changeDate = (SELECT MAX(validTo) FROM dbo.widgetPriceHistory WHERE name = 'grommet')
	WHERE productId = (SELECT TOP(1) productId FROM dbo.widgetPriceHistory WHERE name = 'grommet');
DELETE FROM dbo.widgetPriceHistory
	WHERE name = 'cheese';

ALTER TABLE dbo.widget
	ADD PERIOD FOR SYSTEM_TIME (changeDate, validTo);
ALTER TABLE dbo.widget
	SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.widgetPriceHistory));

SELECT *
	FROM dbo.widget
UNION ALL
SELECT *
	FROM dbo.widgetPriceHistory
ORDER BY productId, changeDate;