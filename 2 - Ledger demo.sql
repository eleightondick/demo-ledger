:ON ERROR EXIT
:SETVAR sqlcmdStatus "Enabled"
IF '$(sqlcmdStatus)' <> 'Enabled'
	RAISERROR('This script must be run in SQLCMD mode. Disconnecting.', 20, 1) WITH LOG;
ELSE IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 16
	RAISERROR('This script requires SQL Server 2022 or higher', 20, 1) WITH LOG;
IF @@ERROR <> 0
	SET NOEXEC ON;
GO

USE [ledgerDemo];

SELECT *
	FROM dbo.employee_legacy;

CREATE TABLE dbo.employee (
	[id] INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
	[name] VARCHAR(25) NOT NULL,
	[salary] INT NOT NULL DEFAULT(0),
	[changeDate] DATE NOT NULL DEFAULT(GETDATE()))
	WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.employeeHistory),
		  LEDGER = ON);

-- Populate our table - the schemas must be identical
EXECUTE sys.sp_copy_data_in_batches N'dbo.employee_legacy', N'dbo.employee';

-- Now let's see what's in our new ledger table
SELECT *
	FROM dbo.employee;
-- What do you notice about the columns returned?

-- Show ledger columns
SELECT id,
       name,
       salary,
       changeDate,
	   ledger_start_transaction_id,
	   ledger_end_transaction_id,
	   ledger_start_sequence_number,
	   ledger_end_sequence_number
	FROM dbo.employee;

-- Show ledger view + transaction details
SELECT e.id,
       e.name,
       e.salary,
       e.changeDate,
       e.ledger_transaction_id,
       e.ledger_sequence_number,
       e.ledger_operation_type,
       e.ledger_operation_type_desc,
       lt.commit_time,
       lt.principal_name,
       lt.table_hashes
	FROM dbo.employee_ledger e
		INNER JOIN sys.database_ledger_transactions lt ON lt.transaction_id = e.ledger_transaction_id;

-- Let's update Jane's salary and look at the ledger view again
UPDATE dbo.employee
	SET salary = salary + ROUND(salary * 0.1, 2),
		changeDate = GETDATE()
	WHERE name = 'Jane';
SELECT e.id,
       e.name,
       e.salary,
       e.changeDate,
       e.ledger_transaction_id,
       e.ledger_sequence_number,
       e.ledger_operation_type,
       e.ledger_operation_type_desc,
       lt.commit_time,
       lt.principal_name,
       lt.table_hashes
	FROM dbo.employee_ledger e
		INNER JOIN sys.database_ledger_transactions lt ON lt.transaction_id = e.ledger_transaction_id;
-- Notice that the update was recorded by the ledger as INSERT + DELETE
-- and that the hash has changed

-- What does the history show?
SELECT *
	FROM dbo.employeeHistory;
SELECT id,
       name,
       salary,
       changeDate,
       ledger_start_transaction_id,
       ledger_end_transaction_id,
       ledger_start_sequence_number,
       ledger_end_sequence_number
	FROM dbo.employee;

-- Now let's create a digest
EXECUTE sp_generate_database_ledger_digest;

-- View the hashes
SELECT *
	FROM sys.database_ledger_blocks;

-- Do a couple more transactions
INSERT INTO dbo.employee (name, salary, changeDate)
	VALUES ('Kris', 77000, GETDATE());
UPDATE dbo.employee
	SET salary = 60000,
		changeDate = GETDATE()
	WHERE salary < 50000;

-- And generate the digest again
EXECUTE sp_generate_database_ledger_digest;
SELECT *
	FROM sys.database_ledger_blocks;

-- Verify the database manually
DECLARE @digestTable TABLE (digestJson NVARCHAR(MAX));
DECLARE @digest NVARCHAR(MAX);
INSERT INTO @digestTable (digestJson)
	EXECUTE sp_generate_database_ledger_digest;
SELECT @digest = digestJson FROM @digestTable;
EXECUTE sys.sp_verify_database_ledger @digest;

-- We can also set the database to automatically generate digests in immutable storage in Azure
-- then use sys.sp_verify_database_ledger_from_digest_storage to verify automatically

-- Create a credential for Azure Blob Storage first: https://learn.microsoft.com/en-us/sql/relational-databases/tutorial-use-azure-blob-storage-service-with-sql-server-2016?view=sql-server-ver16
-- The container name must be sqldbledgerdigests

ALTER DATABASE SCOPED CONFIGURATION
	SET LEDGER_DIGEST_STORAGE_ENDPOINT = 'https://ledgerdemo.blob.core.windows.net';

-- Where are my digests?
SELECT *
	FROM sys.database_ledger_digest_locations;

-- Verify them automatically
-- Credit: https://learn.microsoft.com/en-us/sql/relational-databases/security/ledger/ledger-verify-database?view=sql-server-ver16&preserve-view=true&tabs=t-sql-automatic#run-ledger-verification-for-the-database
DECLARE @digestLocations NVARCHAR(MAX) = (SELECT * FROM sys.database_ledger_digest_locations FOR JSON AUTO, INCLUDE_NULL_VALUES);
SELECT @digestLocations;
EXECUTE sys.sp_verify_database_ledger_from_digest_storage @digestLocations;

-- For demo purposes, turn off automatic digests to save Azure costs
ALTER DATABASE SCOPED CONFIGURATION
	SET LEDGER_DIGEST_STORAGE_ENDPOINT = OFF;