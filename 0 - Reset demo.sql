:ON ERROR EXIT
:SETVAR sqlcmdStatus "Enabled"
IF '$(sqlcmdStatus)' <> 'Enabled'
	RAISERROR('This script must be run in SQLCMD mode. Disconnecting.', 20, 1) WITH LOG;
ELSE IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 16
	RAISERROR('This script requires SQL Server 2022 or higher', 20, 1) WITH LOG;
IF @@ERROR <> 0
	SET NOEXEC ON;
GO

USE [master];

-- Create a credential for Azure Blob Storage: https://learn.microsoft.com/en-us/sql/relational-databases/tutorial-use-azure-blob-storage-service-with-sql-server-2016?view=sql-server-ver16
-- The container name must be sqldbledgerdigests
IF NOT EXISTS (SELECT 'x' FROM sys.credentials WHERE name LIKE '%sqldbledgerdigests') BEGIN
	RAISERROR('You must create an appropriate credential first.', 20, 1) WITH LOG;
	SET NOEXEC ON;
END;

DROP DATABASE IF EXISTS [temporalDemo];
CREATE DATABASE [temporalDemo];

DROP DATABASE IF EXISTS [ledgerDemo];
CREATE DATABASE [ledgerDemo];
ALTER DATABASE [ledgerDemo] SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE [ledgerDemo] SET READ_COMMITTED_SNAPSHOT ON;

DROP DATABASE IF EXISTS [ledgerDbDemo];

USE [temporalDemo];

IF EXISTS (SELECT 'x' FROM sys.tables WHERE name = 'widget') BEGIN
	ALTER TABLE dbo.widget
		SET (SYSTEM_VERSIONING = OFF);
	DROP TABLE IF EXISTS dbo.widget;
	DROP TABLE IF EXISTS dbo.widgetPriceHistory;
END;

IF EXISTS (SELECT 'x' FROM sys.tables WHERE name = 'myTemporalTable') BEGIN
	ALTER TABLE dbo.myTemporalTable
		SET (SYSTEM_VERSIONING = OFF);
	DROP TABLE IF EXISTS dbo.myTemporalTable;
	DROP TABLE IF EXISTS dbo.myTemporalTable_History;
END;

CREATE TABLE dbo.widget (
	[productId] INT NOT NULL CONSTRAINT PK_widget PRIMARY KEY,
	[name] VARCHAR(25) NOT NULL,
	[price] MONEY NOT NULL,
	[changeDate] DATE NOT NULL);
CREATE TABLE dbo.widgetPriceHistory (
	[productId] INT NOT NULL,
	[name] VARCHAR(25) NOT NULL,
	[price] MONEY NOT NULL,
	[changeDate] DATE NOT NULL,
	CONSTRAINT PK_widgetPriceHistory PRIMARY KEY (productId, changeDate));
GO

CREATE TRIGGER dbo.trgUpdateWidgetHistory
	ON dbo.widget
	AFTER UPDATE
AS BEGIN
	SAVE TRANSACTION startOfTrigger;

	BEGIN TRY
		INSERT INTO dbo.widgetPriceHistory (productId, name, price, changeDate)
			SELECT productId, name, price, changeDate FROM Deleted;
	END TRY
    BEGIN CATCH
		ROLLBACK TRANSACTION startOfTrigger;
		RAISERROR ('Trigger trgUpdateWidgetHistory failed', 16, 1);
	END CATCH
END;
GO

INSERT INTO dbo.widget (productId, name, price, changeDate)
	VALUES (1, 'button', 0.25, '7/1/2022'), (2, 'bolt', 3.44, '7/1/2022'), (3, 'nut', 2.53, '7/1/2022'), (4, 'grommet', 0.79, '7/1/2022');
UPDATE dbo.widget
	SET price = price + ROUND((price * 0.05), 2),
		changeDate = '8/12/2022'
	WHERE price > 1.00;
UPDATE dbo.widget
	SET price = price + ROUND((price * 0.05), 2),
		changeDate = '9/17/2022'
	WHERE price < 1.00;
UPDATE dbo.widget
	SET price = price + ROUND((price * 0.05), 2),
		changeDate = '10/4/2022'
	WHERE price > 1.00;
GO

USE [ledgerDemo];

DROP TABLE IF EXISTS dbo.employee_legacy;
DROP TABLE IF EXISTS dbo.employee;
DROP TABLE IF EXISTS dbo.employeeHistory;

CREATE TABLE dbo.employee_legacy (
	[id] INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
	[name] VARCHAR(25) NOT NULL,
	[salary] INT NOT NULL DEFAULT(0),
	[changeDate] DATE NOT NULL DEFAULT(GETDATE()));
INSERT INTO dbo.employee_legacy (name, salary, changeDate)
	VALUES ('Ed', 58000, '7/1/2021'), ('Jane', 47000, '7/1/2021'), ('Olaf', 76000, '7/1/2021'), ('Sara', 85000, '7/1/2021');
GO