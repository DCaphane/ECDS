use [Customer_VOYCCG];

declare	@CCGs varchar(30) = '03Q',
	@multiplier float = 21


set nocount on;

/*
Change across spec descriptions in the referrals data so use Health dimensions as consistent source
  Combine treatment and main spec codes for a full list
*/

/*
with
  specCodes
  as
  (
    select [Main_Code_Text] ,max(isnull(effective_to, getdate())) as 'Latest_Date'
    from [Info-UK-Health-Dimensions].[Data_Dictionary].[Treatment_Function_Code_SCD]
    group by [Main_Code_Text]
  )
  ,LatestSpecCodes
  as
  (
    select c.[Main_Code_Text] as 'specCode' ,c.[Main_Description] as 'specDesc'-- ,lc.Latest_Date
    from [Info-UK-Health-Dimensions].[Data_Dictionary].[Treatment_Function_Code_SCD] c
      inner join specCodes lc
      on c.[Main_Code_Text] = lc.[Main_Code_Text]
        and isnull(c.effective_to, getdate()) = lc.Latest_Date
  )
  ,mainSpecCodes
  as
  (
    select [Main_Code_Text] ,max(isnull(effective_to, getdate())) as 'Latest_Date'
    from [Info-UK-Health-Dimensions].[Data_Dictionary].[Main_Specialty_Code_SCD]
    group by [Main_Code_Text]
  )
  ,LatestMainSpecCodes
  as
  (
    select c.[Main_Code_Text] as 'specCode' ,c.[Main_Description] as 'specDesc'-- ,lc.Latest_Date
    from [Info-UK-Health-Dimensions].[Data_Dictionary].[Main_Specialty_Code_SCD] c
      inner join mainSpecCodes lc
      on c.[Main_Code_Text] = lc.[Main_Code_Text]
        and isnull(c.effective_to, getdate()) = lc.Latest_Date
  )
  select *
  from LatestMainSpecCodes
union
  select *
  from LatestSpecCodes
order by 1

*/


-- practice mappings table and hub/ alliances lookup
exec Customer_VOYCCG.customer.usp_PracticeCodeMapping;

-- Specific Acute Specialties
exec Customer_VOYCCG.customer.usp_acuteSpecs;
-- select * from ##acuteSpecs

with
  ccgCodes
  as
  (
    select CCG_Code ,max(isnull(effective_to, getdate())) as 'Latest_Date'
    from [Info-UK-Health-Dimensions].[ODS].[CCG_Names_And_Codes_England_SCD]
    group by CCG_Code
  )
  ,LatestCCG
  as
  (
    select c.CCG_Code ,c.CCG_Name ,lc.Latest_Date
    from [Info-UK-Health-Dimensions].[ODS].[CCG_Names_And_Codes_England_SCD] c
      inner join ccgCodes lc
      on c.CCG_Code = lc.CCG_Code
        and isnull(c.effective_to, getdate()) = lc.Latest_Date
  )
  ,selCCGs
  as
  (
    select Item as CCGCode
    from customer.usf_splitString(replace(@CCGs, ' ', ''), ',')
  )
  ,workingDays
  as
  (
    select dateadd(dd,-day(Full_Date)+1, Full_Date) as 'Period'
			,sum (working_Day_Calc) as 'WDays'
    from [Info-UK-Health-Dimensions].[dbo].[ref_Dates]
    where Full_Date between '20120401' and '20200331'
    group by dateadd(dd,-day(Full_Date)+1, Full_Date)
  ),
  /*
  Following are used to change descriptions to codes
    Need to export these are .csv 
  */
  idGPPractice as (
  select ROW_NUMBER() OVER(ORDER BY coalesce(p.PracticeCode_Mapped, reggppraccode, 'V81999') ASC) AS RowNo, coalesce(p.PracticeCode_Mapped, reggppraccode, 'V81999') as 'gp_practice'
    from Customer_VOYCCG.customer.Referrals_RCB r
  left join ##PracticeMapping p
    on r.reggppraccode = p.PracticeCode_Org
    group by coalesce(p.PracticeCode_Mapped, reggppraccode, 'V81999')
  ),
  idCCG as (
    select ROW_NUMBER() OVER(ORDER BY ccg ASC) AS RowNo, ccg
    from Customer_VOYCCG.customer.Referrals_RCB
    group by ccg
  ),
  idRefMethod as (
    select ROW_NUMBER() OVER(ORDER BY replace(replace(referral_method, '"', ''), '''', '') ASC) AS RowNo, replace(replace(referral_method, '"', ''), '''', '') as 'referral_method'
    from Customer_VOYCCG.customer.Referrals_RCB
    group by replace(replace(referral_method, '"', ''), '''', '')
  ),
  idRefUrgency as (
    select ROW_NUMBER() OVER(ORDER BY referral_urgency ASC) AS RowNo, referral_urgency
    from Customer_VOYCCG.customer.Referrals_RCB
    group by referral_urgency
  ),
  idRefType as (
    select ROW_NUMBER() OVER(ORDER BY referral_type ASC) AS RowNo, referral_type
    from Customer_VOYCCG.customer.Referrals_RCB
    group by referral_type
    ),
  idRefRoleType as (
    select ROW_NUMBER() OVER(ORDER BY referring_role_type ASC) AS RowNo, referring_role_type
    from Customer_VOYCCG.customer.Referrals_RCB
    group by referring_role_type
    ),
  idCancer as (
    select ROW_NUMBER() OVER(ORDER BY cancer ASC) AS RowNo, cancer
    from Customer_VOYCCG.customer.Referrals_RCB
    group by cancer
    ),
  maxDate as(
    select max(referral_made_date) as 'maxDate'
    from Customer_VOYCCG.customer.Referrals_RCB
    )
select idCCG.RowNo as 'ccg'
     ,idGPPractice.RowNo as 'gp_practice'
    --, cast(Datediff(s, '1970-01-01', referral_made_date) AS BIGINT) * 1000 as 'Referral_Date_ms'
     ,cast(Datediff(s, '1970-01-01', dateadd(dd, 1 - datepart(dd, referral_made_date), referral_made_date)) as bigint) * 1000 as 'Period_ms'
     ,cast(Datediff(s, '1970-01-01', DATEADD(dd, -(DATEPART(dw, referral_made_date)-1), referral_made_date)) as bigint) * 1000 as 'WeekCommencing'
    --, cast(Datediff(s, '1970-01-01', DATEADD(dd, 7-(DATEPART(dw, referral_made_date)), referral_made_date)) AS BIGINT) * 1000 as 'WeekEnding'
     ,referred_to_specialty_code as 'SpecCode'
     ,idRefMethod.RowNo as 'referral_method'
     ,idRefUrgency.RowNo as 'referral_urgency'
     ,idRefType.RowNo as 'referral_type'
     ,isnull(idRefRoleType.RowNo, 1) as 'referring_role_type'
     ,isnull(idCancer.RowNo, 1) as 'cancer'
     ,sum(referral_count) as 'ref_count'
	 -- ,sum(cast(referral_count as float) / cast(w.WDays as float) * @multiplier) as 'ref_count_std'
from Customer_VOYCCG.customer.Referrals_RCB r
  left join ##PracticeMapping p
    on r.reggppraccode = p.PracticeCode_Org
  left join LatestCCG c
    on r.ccg = c.ccg_Code
  --inner join selCCGs s
  --	on r.ccg = s.CCGCode
  left join workingDays w
    on r.referral_received_month = w.Period
  left join ##acuteSpecs ga
    on r.referred_to_specialty_code = ga.spec_code
  -- reference tables
  left join idGPPractice
    on coalesce(p.PracticeCode_Mapped, reggppraccode, 'V81999') = idGPPractice.gp_practice
  left join idCCG
    on r.ccg = idCCG.ccg
  left join idRefMethod
    on replace(replace(r.referral_method, '"', ''), '''', '') = idRefMethod.referral_method
  left join idRefUrgency
    on r.referral_urgency = idRefUrgency.referral_urgency
  left join idRefType
    on r.referral_type = idRefType.referral_type
  left join idRefRoleType
    on r.referring_role_type = idRefRoleType.referring_role_type
  left join idCancer
    on r.cancer = idCancer.cancer
  left join maxDate md
    on r.referral_made_date <= md.maxDate
where isnull(referral_made_date, '19000101') > '20170101' -- data quality issues in data before this
        -- Week commencing is within last week to prevent data from dropping off
  and datediff(day, md.maxDate, DATEADD(dd, -(DATEPART(dw, referral_made_date)-1), referral_made_date)) < -6
  and r.ccg = '03Q'
group by idCCG.RowNo
    ,idGPPractice.RowNo
    --, cast(Datediff(s, '1970-01-01', referral_made_date) AS BIGINT) * 1000
    , cast(Datediff(s, '1970-01-01', dateadd(dd, 1 - datepart(dd, referral_made_date), referral_made_date)) as bigint) * 1000
    , cast(Datediff(s, '1970-01-01', DATEADD(dd, -(DATEPART(dw, referral_made_date)-1), referral_made_date)) as bigint) * 1000
    --, cast(Datediff(s, '1970-01-01', DATEADD(dd, 7-(DATEPART(dw, referral_made_date)), referral_made_date)) AS BIGINT) * 1000
    , referred_to_specialty_code
    , idRefMethod.RowNo
    , idRefUrgency.RowNo
    , idRefType.RowNo
    , isnull(idRefRoleType.RowNo, 1)
    , isnull(idCancer.RowNo, 1)
