Explanation:
Database used: Teradata Studio	
This SQL code is extracting data from multiple tables and will be exported as one file and uploaded into an excel database sheet I created. 
The excel sheet will autopopulate based on the extracted data and create aggregated stats, where you can also filter the data. 
Data is looking at a specific population of student customers to understand customer behavior- students imported, imported date, refund selection choice/preference, and financial aid disbursements

Techniques Used:
CTEs, Joins (inner & left), data cleanup (date formatting), CASE Statements, aggregate functions (SUM, COUNT), NULL,filtering, dedupe data using MAX wrapped in a case statement, GROUP BY

Notes:
Newest Additions:
Re-formatted date function for data pull
added in another CTE for ALL total financial aid disbursements, regardless of OPT IN as pref
Added in 90 day active count in main CTE for those that pref selection intially was NOT OPT IN, but ended up with an OPT IN account at some point

----------CODE------------------------

--list of all customer imports in last 24 full months + their initial selection preference + their schoolid. Here is where I'm also going to bring in school data so we have the 3 filters we need for schools

--customer preferences & imports CTE
With Pref as(
SELECT 
DISTINCT
to_char(c.dcustimportdate, 'MM-YYYY') as "Import_Month",
s.nschoolid, 
s.sidcardstate,
s.stermstate,
s.ssostate,
c.odm_ds_customerinfo_key,
cp.sinitfinaidprefcode
FROM Customerinfo c
JOIN CustomerPreferences cp
	on c.nuserid = cp.nuserid 
JOIN schoolsettings s
	on c.nschoolid = s.nschoolid 
--exclude test schools
	AND s.nschoolid NOT IN (0,616,617,623,800,900,909) 
join VD_MSTR_D_DAY d
	on c.dcustimportdate=d.ddate
WHERE c.dcustimportdate>= trunc(add_months(current_date - EXTRACT (DAY FROM current_date) + 1,-24),'mm')
),


--customers that have had a OPT IN checking account at some point, and those that are also 90 day active

OPT IN_ACCOUNTS as(
SELECT
DISTINCT
m.odm_ds_customerinfo_key,

--want to get rid of dupes so idea is to get have just a --customerID and a flag to if they have an active or inactive --acct. everyone in the table by default will have an acct. the --MAX will show us if at least one of their accts is active.

max(CASE WHEN aa.odm_as_accountinfo_key IS NOT NULL then 1 else 0 end) as Active90_Flag
FROM ACCOUNTHISTORY_CURRENT ahc
JOIN PRODUCTCODE pc
--adding in archived product codes
	on ahc.odm_as_cbsproductcode_key = pc.odm_as_cbsproductcode_key AND pc.nproductcode IN (100,110,101,111) 	--OPT IN Checking Accounts only
JOIN VF_EW_ACCT_CUST_MAP m
	on ahc.odm_as_accountinfo_key = m.odm_as_accountinfo_key 
LEFT JOIN Active_acct_strict_90_days aa
	on ahc.odm_as_accountinfo_key = aa.odm_as_accountinfo_key AND aa.dactiveaccountdate=current_date -3 	--(who was 90 day active as of yesterday)
GROUP BY 1
),

--who also has a savings account at some point? 
Savings as (
SELECT
DISTINCT m.odm_ds_customerinfo_key,
max(CASE WHEN aa.odm_as_accountinfo_key IS NOT NULL then 1 else 0 end) as Active90_Flag
FROM ACCOUNTHISTORY_CURRENT ahc
JOIN PRODUCTCODE pc
	on ahc.odm_as_cbsproductcode_key = pc.odm_as_cbsproductcode_key AND pc.nproductcode IN (400,401) --OPT IN Savings Account cant have savings account without a OPT IN checking account fyi
JOIN VF_EW_ACCT_CUST_MAP m
	on ahc.odm_as_accountinfo_key = m.odm_as_accountinfo_key
LEFT JOIN VD_AS_Active_acct_strict_90_days aa
	on ahc.odm_as_accountinfo_key = aa.odm_as_accountinfo_key AND aa.dactiveaccountdate=current_date -3 	--(who was 90 day active as of yesterday)
GROUP BY 1
),

OPTIN_FinAid as(
SELECT
a11.odm_ds_customerinfo_key,
--going to sum here because we dont care about individual amts.	
sum(a11.ndisbursementamount) as TotalDisbIntoVIBE
FROM VF_DS_FINAIDDISBURSEMENT a11		--includes customerinfo_key
JOIN VD_DS_FINAIDDISBURSEMENT a12
	ON a11.odm_ds_finaiddisbursem_key = a12.odm_ds_finaiddisbursem_key
JOIN Pref p --gonna join on pref instead of OPT IN to see if there are any data issues
	on a11.odm_ds_customerinfo_key = p.odm_ds_customerinfo_key
WHERE a12.bfinaiddisbexcluderpts in (0)
AND sfinaiddisbstatuscategory IN ('OneAccount') --means they received the financialaid to a OPT IN account? 			
group by 1
),


--***NEW CTE Added**--
--All up total of Financial Aid disbursements for imported customers/students
AllFinAid as(
SELECT 
a11.odm_ds_customerinfo_key,
SUM(a11.ndisbursementamount) as TotalDisb_ALL
FROM VF_DS_FINAIDDISBURSEMENT a11
JOIN VD_DS_FINAIDDISBURSEMENT a12
	ON a11.odm_ds_finaiddisbursem_key = a12.odm_ds_finaiddisbursem_key
JOIN Pref p --gonna join on pref instead of OPT IN to see if there are any data issues
	on a11.odm_ds_customerinfo_key = p.odm_ds_customerinfo_key
WHERE a12.bfinaiddisbexcluderpts in (0)
AND a12.sfinaiddisbstatuscategory in ('ACH', 'Check', 'OneAccount', 'UFO Check') --this removes any 'in-process', 'returned' checks 	
and a12.bfinaiddisbexcluderpts = 0
group by 1
)


--FINAL OUTPUT:
SELECT
distinct
p."Import_Month",
p.sidcardstate,
p.stermstate,
p.ssostate,

--Imports & Initial Refund Preference Selection--
COUNT(distinct p.odm_ds_customerinfo_key) as "TTL_Students_Imported",	--pop. of all students added to our system
COUNT(DISTINCT CASE WHEN p.sinitfinaidprefcode <>'NOP' THEN p.odm_ds_customerinfo_key END) as RefundSelection,		--all initial choices 	
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('ACH') THEN p.odm_ds_customerinfo_key END) AS TTL_ACH_Selection,	--the 3 here are subsets of the one above (refund selection) 
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') THEN p.odm_ds_customerinfo_key END) as TTL_OPTIN_Selection,
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('CHK') THEN p.odm_ds_customerinfo_key END) as TTL_Check_Selection,

--Initial Preference= OPT IN--
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') AND v.odm_ds_customerinfo_key IS NOT NULL Then p.odm_ds_customerinfo_key end) as OPTIN_Sel_OPTIN_Opened,
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') AND v.odm_ds_customerinfo_key IS NOT NULL and v.Active90_Flag=1 Then p.odm_ds_customerinfo_key end) OPTIN_Sel_Active90_Flag,   

--Initial Preference was NOT OPT IN, but they ended up having a OPT IN account at some point--
COUNT(distinct CASE WHEN p.sinitfinaidprefcode <>'DIR' AND v.odm_ds_customerinfo_key IS NOT NULL Then p.odm_ds_customerinfo_key end) as NoSel_OPTINOpened,
COUNT(distinct CASE WHEN p.sinitfinaidprefcode <>'DIR' AND v.odm_ds_customerinfo_key IS NOT NULL and v.Active90_Flag=1 Then p.odm_ds_customerinfo_key end) OPTIN_NoSel_Active90_Flag, 

--SAVINGS related--
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') AND v.odm_ds_customerinfo_key IS NOT NULL AND s.odm_ds_customerinfo_key IS NOT NULL Then p.odm_ds_customerinfo_key end) as Savings_ChoseOPTIN_Selection,
COUNT(distinct CASE WHEN p.sinitfinaidprefcode <> 'DIR' AND v.odm_ds_customerinfo_key IS NOT NULL AND s.odm_ds_customerinfo_key IS NOT NULL Then p.odm_ds_customerinfo_key end) as NoSel_Has_Savings,
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') AND s.odm_ds_customerinfo_key IS NOT NULL and s.Active90_Flag=1 Then p.odm_ds_customerinfo_key end) Savings_Sel_Active90_Flag,

--OPT IN Financial AID--
COUNT(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') AND f.odm_ds_customerinfo_key IS NOT NULL THEN p.odm_ds_customerinfo_key end) as OPTIN_Sel_Received_FinAid,		--finAid table only shows finaid for OPTIN account holders-
SUM(distinct CASE WHEN p.sinitfinaidprefcode IN ('DIR') AND f.odm_ds_customerinfo_key IS NOT NULL THEN f.TotalDisbIntoOPTIN END) as OPTIN_Sel_Amount_Disbursed_OPTIN,

--FinAid where eventually they opened a OPT IN account--
COUNT(distinct CASE WHEN p.sinitfinaidprefcode <> 'DIR' AND f.odm_ds_customerinfo_key IS NOT NULL THEN p.odm_ds_customerinfo_key end) as NoSel_Received_FinAid,	
SUM(distinct CASE WHEN p.sinitfinaidprefcode <> 'DIR' AND f.odm_ds_customerinfo_key IS NOT NULL THEN f.TotalDisbIntOPTIN END) as NoSel_Amount_Disbursed_OPTIN,

--All Financial Aid--
COUNT(distinct CASE WHEN a.odm_ds_customerinfo_key IS NOT NULL THEN p.odm_ds_customerinfo_key end) as Total_FinAid_Disbursed,	
SUM(distinct CASE WHEN a.odm_ds_customerinfo_key IS NOT NULL THEN a.TotalDisb_ALL END) as Total_FinAid_Amount_Disbursed

FROM pref p --show me all preferences from preferences table
LEFT JOIN VIBE_Accounts v --show me everything from preferences tables, and those that have an OPT IN account and chose direct deposit
	on p.odm_ds_customerinfo_key = v.odm_ds_customerinfo_key
LEFT JOIN savings s
	on p.odm_ds_customerinfo_key = s.odm_ds_customerinfo_key 
LEFT JOIN OPTIN_FinAid f
	on p.odm_ds_customerinfo_key = f.odm_ds_customerinfo_key 
LEFT JOIN ALLFinAid a
	on p.odm_ds_customerinfo_key = a.odm_ds_customerinfo_key
GROUP BY 1,2,3,4


