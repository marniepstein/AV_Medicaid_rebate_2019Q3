/***************************************************************************
Project: Medicaid Spending on 3 Drugs, Quarterly Updates

Purpose: This program reads in all of the data that will be used in P3B in order to estimate the Medicaid rebate.

Author: Marni Epstein

Date: July 2019
Updated: March 2020

Input files: many
Output files: many

***************************************************************************/

/***********************
SET GLOBALS - CHANGE
***********************/

*Enter user (computer name)
global user = "MEpstein"

*Enter last year and quarter that we have SDUD data 
global lastyr = 2019
global lastqtr = 3

*Enter today's date to create unique log
global today=031220

*Enter drive letter
*global drive = "C"
global drive = "D"

/****************************************************************
UPDATE DIRECTORIES - WILL UPDATE AUTOMATED BASED ON GLOBALS ABOVE
****************************************************************/

cd "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Data"
global rebate "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Medicaid rebate adjustments incl inflation"
global medicaid "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\Medicaid enrollment data"
global nadac "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\NADAC"
global asp "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\ASP"
global ful "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\FUL Weighted AMP"
global output "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Medicaid rebate adjustments incl inflation"
global dispensefee "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\Dispensing Fees"
global fss "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\Federal Supply Schedules"
global ndcunits "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\NDC numbers\Units per package"

/********************************************************************************************************************
Create dataset of CPI-U values. Each quarter gets the same CPI-U value (i.e. all 2015 Q2 records get the same CPI-U) 
Following Sean's methods, use the month prior to the quarter (i.e. Dec of the year before for Q1, March for Q2, etc).
	* Quarter 1 = December of the year prior
	* Quarter 2 = March
	* Quarter 3 = June
	* Quarter 4 = Sep
	
Re-download the CPI-U spreadsheet with each new update to get the newest CPI quarter.
	* Go to https://data.bls.gov/cgi-bin/srgate
	* Enter the series ID CUUR0000SA0 and click Next
	* Select table format, specify the year range from 1985 - the current year, original data value, all time periods,
			output type HTML table, and click retrieve data. On the next page, click on download as .xlsx.
********************************************************************************************************************/

*CHANGE filename and cell range if there is a new year
import excel using "${rebate}/CPI-U Data/CPI_U SeriesReport-20200312155007_a65166.xlsx", cellrange(A12:M48) firstrow clear

*Assign months for each quarter
rename Dec CPI_1
rename Mar CPI_2
rename Jun CPI_3
rename Sep CPI_4

drop Jan Feb Apr May Jul Aug Oct Nov

reshape long CPI_, i(Year) j(quarter)
rename CPI_ CPI
rename Year year
label variable CPI "Consumer Price Index for all urban consumers (CPI-U)"

*Quarter 1 comes from Dec of the previous year, so we actually want to assign it to the year for quarter 1
replace year = year + 1 if quarter == 1
sort year quarter

*Drop quarters that we don't yet have data for
drop if CPI == .

save "CPI_U.dta", replace


/****************************************************************
Read in list of NADACs. 
From: https://data.medicaid.gov/Drug-Pricing-and-Payment/NADAC-National-Average-Drug-Acquisition-Cost-/a4y5-998d
Saved: D:\Users\MEpstein\Box\LJAF Medicaid SDU\1 Data\NADAC

NDCs that have a NADAC are not 5i drugs
****************************************************************/

import delimited using "${nadac}/NADAC_as_of_2013-12.csv", varnames(1) clear
gen ndc_s11  = string(ndc,"%011.0f")
gen year = 2013
gen quarter = 4

local a "01 04 07 10"
forvalues year = 2014/2018 {
	forvalues n = 1/4 {
	
		local month : word `n' of `a'
		di "`year' `month'"
		
		tempfile temp1
		save "`temp1'"
		
		import delimited using "${nadac}/NADAC_as_of_`year'-`month'.csv", varnames(1) clear
		gen ndc_s11  = string(ndc,"%011.0f")
		gen year = `year'
		gen quarter = `n'
		
		append using "`temp1'"
	}
}

local a "01 04 07"
forvalues year = 2019/2019 {
	forvalues n = 1/3 {
	
		local month : word `n' of `a'
		di "`year' `month'"

		tempfile temp1
		save "`temp1'"
		
		import delimited using "${nadac}/NADAC_as_of_`year'-`month'.csv", varnames(1) clear
		gen ndc_s11  = string(ndc,"%011.0f")
		gen year = `year'
		gen quarter = `n'

		append using "`temp1'"
	}
}

*Gen NDC-9
gen ndc_s9 = substr(ndc_s11, 1, 9)

*Create average NADAC across NDC-9s
bys ndc_s9 year quarter: egen avg_NADAC_unit = mean(nadac_per_unit)

*Count NDC-11s per NDC-9
bys ndc_s9 year quarter: egen countndc = count(ndc_s11)
sort year quarter ndc_s11

*Check when the NADAC for the average across NDC-9 is different than the NDC-11
replace nadac_per_unit = round(nadac_per_unit, 0.00001)
replace avg_NADAC_unit = round(avg_NADAC_unit, 0.00001)
count if avg_NADAC_unit != nadac_per_unit

*Check how different it is
gen avgratio_NADAC =  nadac_per_unit / avg_NADAC_unit
count if (avgratio_NADAC < .75 | avgratio_NADAC > 1.25) & countndc > 1 & year >= 2010

*Keep only one obs per NDC-9, and use avg_NADAC_unit
duplicates drop ndc_s9 year quarter, force
keep ndc_s9 year quarter avg_NADAC_unit

save "nadac_ndc.dta", replace

*Create unique list of NDCs at the NDC-9 level - drop duplicates from year and quarter
duplicates drop ndc_s9, force
save "nadac_unique_ndc.dta", replace


/****************************************************************
ASP files: https://www.cms.gov/Medicare/Medicare-Fee-for-Service-Part-B-Drugs/McrPartBDrugAvgSalesPrice/2019ASPFiles
For each quarter, odwnload the ASP pricing file (which is by HPCPS) and the NDC-HCPCS crosswalk
Saved: Box\LJAF Medicaid SDU\1 Data\ASP

Read in ASP files. These come at the HCPCS level with a HCPCS to NDC crosswalk
We will use ASP for 5i drugs to calcualte AMP
****************************************************************/

local a "1 2 3 4"
local b "January April July October"

forvalues year = 2006/2019 {

	forvalues n = 1/4 {
		local quarter : word `n' of `a'
		local month : word `n' of `b'
  
		di "`year' Q`quarter' `month'"
  
		*Read in HCPCS to NDC crosswalk. Note that there are duplicate HCPCS that go to different NDCs
		import excel using "${asp}/`month' `year' ASP NDC-HCPCS Crosswalk.xls",  cellrange(A7) clear
		rename A HCPCSCode
		rename B SHORTDESCRIPTOR
		rename C LABELERNAME
		rename D NDC2
		keep HCPCSCode SHORTDESCRIPTOR LABELERNAME NDC2
		drop if HCPCSCode == ""
		drop if LABELERNAME == "LABELER NAME"
		
		*Drop if there are duplicate entries for a HCPCS code that goes to the same NDC
		di "Drop duplicate HCPCS codes that goes to the same NDCs"
		duplicates drop HCPCSCode NDC2, force

		di "Count how many NDCs are not properly formatted as 5-4-2" 
		count if length(NDC2) != 13
		
		*Format NDC variable to the ndc_s11 (11 character string) format that we use
		gen ndc_s1 = substr(NDC2, 1, 5)
		gen ndc_s2 = substr(NDC2, 7, 4)
		gen ndc_s3 = substr(NDC2, 12, 2)
		egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)

		*Save as temp file.
		tempfile temp1
		save "`temp1'"

		*Read in pricing file. We will assign the ASP prices to the duplicate HCPCS, since we work at the NDC level
		import excel using "${asp}/`month' `year' ASP Pricing File.xls",  cellrange(A10) firstrow clear
		rename PaymentLimit ASP
		
		/*Check if the Notes column indicates that AMP was substituted for ASP
		If, so, it will contian the value "AMP-based payment limit"
		*/
		gen notes_AMPsub = Notes == "AMP-based payment limit"
		keep HCPCSCode ShortDescription HCPCSCodeDosage ASP Notes notes_AMPsub

		
		*Check that there is only one ASP per HCPCS code
		drop if HCPCSCode == ""
		di "Check that there is only one ASP per HCPCS code"
		duplicates report HCPCSCode

		*Merge ASPs onto HCPCS/NDC crosswalk
		*_m == 1 are ASPs where the HCPCS doesn't have a corresponding entry in the HCPCS/NCD crosswalk. We can't do anything with them
		*_m = =2 are entries in the crosswalk that don't have an ASP for this quarter.
		merge 1:m HCPCSCode using "`temp1'"
		keep if _m == 3
		drop _m

		*Assign year and quarter variables - THERE IS A 2 QUARTER LAG BETWEEN THE FILES AND THE DATA THEY CORRESPOND TO 
		if `quarter' == 1 | `quarter' == 2 {
			gen year = `year' - 1
			gen quarter = `quarter' + 2
		}
		else if `quarter' == 3 | `quarter' == 4 {
			gen year = `year'
			gen quarter = `quarter' - 2
		}
		
		*Make sure ASP variable is numeric
		destring ASP, replace
		
		*If this is NOT the first quarter (2010 Q1), append onto existing accumulating file
		if "`year'" == "2006" & "`quarter'" == "1" {
			*Save whole file, this is the first quarter
			tempfile temp2
			save "`temp2'"	
		}
		else {
			append using "`temp2'"
			di "Appended `year' Q`quarter' `month' onto accumulating file"
			
			*Save whole file, including newly appended quarter if not 2010 Q1
			tempfile temp2
			save "`temp2'"
		}
		
	} // End quarter loop 
	
} //End year loop

*Check that all years/quarters were read in properly AND that the 2 quarter lag was applied
tab year quarter

*Check how many of these entries are marked as AMP having been substituted for ASP
tab year quarter if notes_AMP == 1

*Some NDCs are not properly formatted as 5-4-2. Count the total and check that none of them are our drugs of interest
count if length(NDC2) != 13
tab ShortDescription if length(NDC2) != 13

*These are all from 2005 so it's ok to drop them
*br if inlist(ShortDescription, "Buprenorphine hydrochloride", "Inj nalbuphine hydrochloride", "Inj naloxone hydrochloride") & length(NDC2) != 13

*Drop these NDCs, assuming none of them are our drugs of interst
drop if length(NDC2) != 13

label variable ASP "ASP + 6%"

*Reduce the reported ASP+6% to ASP
gen redASP = ASP / 1.06
label variable redASP "ASP, reduced from reported ASP+6% to just ASP"

/******
Get rid of any duplicate NDC/year/quarter/ASP entries. These occur because different HCPCS codes point to the same NDC,
and so an NDC can get multiple ASPs assigned to it (since ASP is from HCPCS code)
We average the ASPs and mark which ones are duplicated to check if they are our drugs of interest later
*******/
duplicates tag ndc_s11 year quarter, gen(dupASP)

*If multiple ASP values for the same NDC in a quarter, use the averge
bys ndc_s11 year quarter: egen redASP_dedup = mean(redASP)
replace redASP = redASP_dedup
drop redASP_dedup

duplicates drop ndc_s11 year quarter, force
tab dupASP
label variable dupASP "This NDC in this quarter had 2+ ASP values, redASP is the average"

*Gen NDC-9
egen ndc_s9 = concat(ndc_s1 ndc_s2)

*Rename the dosage variable and make sure we keep this in the dataset
rename HCPCSCodeDosage ASPdosage

*Check the 2 Sublocade NDC-9s that have multiple dosage values
tab ndc_s11 ASPdosage if ndc_s9 == "124960100"
tab ndc_s11 ASPdosage if ndc_s9 == "124960300"


*Collapse down to NDC-9
bys ndc_s9 year quarter: egen ndc9_redASP = mean(redASP)

*Count NDC-11s per NDC-9
bys ndc_s9 year quarter: egen countndc = count(ndc_s11)
sort year quarter ndc_s11

*Check when the redASP for the average across NDC-9 is different than the NDC-11
replace redASP = round(redASP, 0.00001)
replace ndc9_redASP = round(ndc9_redASP, 0.00001)
count if ndc9_redASP != redASP
*br ndc_s11 ndc_s9 redASP avg_redASP countndc year quarter if avg_redASP != redASP & countndc > 1 & year >= 2010

*Check how different it is
gen avgratio_redASP =  ndc9_redASP / redASP
count if (avgratio_redASP < .8 | avgratio_redASP > 1.2) & countndc > 1 & year >= 2010

*Drop duplicates by NDC-9 within each year and quarter
duplicates drop ndc_s9 year quarter, force

keep year quarter ndc_s9 ndc9_redASP notes_AMPsub Notes ASPdosage

save "ASP.dta", replace



/****************************************
Read in weighted AMP data from FUL files 
From: https://data.medicaid.gov/Drug-Pricing-and-Payment/weighted-AMP/mkit-8833
Saved: Box\LJAF Medicaid SDU\1 Data\FUL Weighted AMP
****************************************/
*NOTE: Add new year/quarter if new file is added
global fulyrqtr "2016_04 2016_07 2016_10 2017_01 2017_04 2017_07 2017_10 2018_01 2018_04 2018_07 2018_10 2019_01 2019_04 2019_07"

foreach yrqtr in $fulyrqtr {
	
	di "FUL file `yrqtr'"

	import delimited using "${ful}/Federal_Upper_Limits_-_`yrqtr'.csv", clear
	
	*For some reason, the 2017_01 file has data for all months. Only keep for month 1
	if "`yrqtr'" == "2017_01" {
		keep if month == 1
	}
	
	*2019-04 and 2019_07 are NDCs saved as "XXXXX-XXXX-XX"
	if "`yrqtr'" == "2019_04" | "`yrqtr'" == "2019_07" {
	*Pad with zeros to get to the 5-4-2 format
		gen ndc_s1  = substr(ndc,1, 5)
		gen ndc_s2  = substr(ndc, 7, 4)
		gen ndc_s3  = substr(ndc, 12, 2)

		*Create NDC-11 string
		egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)
	}
	*In the other years, NDC is saved as numeric
	else {
		gen ndc_s11 = string(ndc,"%011.0f")
	}
	
	gen quarter = .
	replace quarter = 1 if month == 1
	replace quarter = 2 if month == 4
	replace quarter = 3 if month == 7
	replace quarter = 4 if month == 10
	
	di "Duplicates for `yrqtr'"
	duplicates report ndc_s11
	
	keep year quarter ndc_s11 weightedaverageamps
	
	*Append to file
	*If first year/quarter, save
	if "`yrqtr'" == "2016_04" {
		tempfile temp1
		save "`temp1'"
	}
	else {
		append using "`temp1'"
		save "`temp1'", replace
	}

}

tab year quarter 
label variable weightedaverageamps "Weighted AMP from FUL file"

*Make sure there are no duplicate entries. 2017_01 came in with data for all months, check this doesn't happen in future files
duplicates report year quarter ndc_s11

*Create NDC-9
gen ndc_s9 = substr(ndc_s11, 1, 9)

*Drop duplicates by NDC-9 that have the same weighted AMP value
duplicates drop ndc_s9 weightedaverageamps year quarter, force

*Check how many NDC-9 duplicates are left with different weighted AMP
duplicates tag ndc_s9 year quarter, gen(dup)
bys ndc_s9 year quarter: egen avg_weightedAMP = mean(weightedaverageamps)

*Check how different the average value is from the individual valuess for the duplicates
gen test = weightedaverageamps / avg_weightedAMP

*All values are within 10% of the average
count if (test > 1.1 | test < 0.9) & dup > 1

*Only keep one obs per NDC-9
duplicates drop ndc_s9 year quarter, force
keep ndc_s9 avg_weightedAMP year quarter

*Save weighted AMP from FUL files
save "weightedamp_ful.dta", replace



/****************************************************************
Read in NDC units 
Note: We read in FSS units below. With the exception of the 1 Narcan NDC, FFS units are always equal to NDC units
****************************************************************/

/*******************************************
If this is not the first round, start with latest (last quarter's) NDC list 
*******************************************/
import excel using "${ndcunits}/Units per RX Complete_final_2019Q2.xlsx", firstrow clear
drop SDUDmeduntsrx newndc

*Merge in list and units/rx from this quarter
*This file, ndcunits_${lastyr}Q${lastqtr}.dta, is created in P3B - a little weird, have to run up until then before you can run below
merge 1:1 ndc_s11 using "ndcunits_${lastyr}Q${lastqtr}.dta"
order ndc ndc_s11 drugtype Generic meduntsrx
rename meduntsrx SDUDmeduntsrx

*For 2019 Q2 there are 6 new NDCs that we need to get package info for
sort ndc_s11
gen newndc = "New NDC this quarter" if _m == 2
drop _m

*Export this list to excel
export excel using "${ndcunits}/Units per RX Complete_addnewNDCs_${lastyr}Q${lastqtr}.xlsx", firstrow(variables) replace

/*************** 
BY HAND: Open up this excel file and add in information for the new NDCs
Fill in dosage form and billing unit, looking up NDC online. Also fill in package description from online and package units to reflect the units on the packagesize
Fill in "Finalunitsperpackage" as the number of units we'll use. We mostly use the units from the package description unless there is a huge discrepancy, and if so, add a note in.
	For mL, leave blank. Note that when the package size is 1, we end up using SDUD units instead of multiplying rx * units per package.
Save as "Units per RX Complete_final_${lastyr}Q${lastqtr}.xlsx" and then read back in
***************/
import excel using "${ndcunits}/Units per RX Complete_final_${lastyr}Q${lastqtr}.xlsx", firstrow clear
drop LCCnotes MEsresponses P newndc


replace Finalunitsperpackage = "" if Finalunitsperpackage == "ML - use SDUD median"
destring Finalunitsperpackage, replace
replace FSSUnitstouse = Finalunitsperpackage if FSSUnitstouse == .

*We use units = 2 (EA) instead of 0.2 (ML) for Narcan
replace FSSUnitstouse = 2 if ndc_s11 == "69547035302"

keep ndc_s11 drugtype Generic DosageForm BillingUnit PackageDescription PackageUnits Finalunitsperpackage FSSUnitstouse

save "ndcunits.dta", replace




/****************************************************************
Read in Federal Supply Schedule data
From: https://www.va.gov/oalc/foia/library.asp#two
Saved: Box\LJAF Medicaid SDU\1 Data\Federal Supply Schedules

Note: You have to run P3B up until the point where ndcunits.dta is created
****************************************************************/
local monthlist "01 04 07 10"

tempfile temp1
forvalues year = 2010/2019 {
	forvalues n = 1/4 {
	
		local month : word `n' of `monthlist'
		di "`year' Q`n', month = `month'"
		
		*For some reason, there is no 2010 10 (Q3) file. For this quarter, use the prices from the quarter before
		if "`year'" == "2012" & "`month'" == "10" {
			local month = "07"
		}
		
		*2017 and later is .xlsx, before is .xlsx
		if `year' > 2016 {
			local ext = "xlsx"
		}
		else {
			local ext = "xls"
		}
		
		import excel using "${fss}/foiaVApharmaceuticalPrices_`year'_`month'.`ext'", firstrow clear
		
		keep ContractStartDate ContractStopDate NDCWithDashes PackageDescription Generic TradeName Price PriceStartDate PriceStopDate PriceType
		tostring ContractStartDate ContractStopDate NDCWithDashes PackageDescription Generic TradeName Price PriceStartDate PriceStopDate PriceType, replace
		gen year = `year'
		gen quarter = `n'
		
		if "`year'" == "2010" & "`month'" == "01" {
			save "`temp1'"
		}
		else {
			append using "`temp1'", force
			save "`temp1'", replace
		}
	}
}

*Format NDC variable
gen ndc_s1 = substr(NDCWithDashes, 1, 5)
gen ndc_s2 = substr(NDCWithDashes, 7, 4)
gen ndc_s3 = substr(NDCWithDashes, 12, 2)
egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)
egen ndc_s9 = concat(ndc_s1 ndc_s2)

sort ndc_s11 year quarter
rename Generic Generic_FSS

save "fss_raw.dta", replace

use "fss_raw.dta", clear

*Merge in NDC list and only keep NDCs that we are interested in
merge m:m ndc_s9 using "ndc_short.dta"

*Tab manufacturers from our sample NDC list
tab ndc_s1 if _m == 3
gen big4 = 1 if PriceType == "Big4"
bys ndc_s1 year quarter: egen countbig4 = total(big4)

egen yearquarter = concat(year quarter)

* _m == 1 are values that are in FSS but not on our NDC list
* _m == 2 are values on our NDC list that don't appear in the FSS data
keep if _m == 3
drop _m

/**** 
Look at which NDCs also have an entry for big4
*****/
tab PriceType, m
tab ndc_s11 Generic if PriceType == "Big4"

*There is price data for FFS, Big 4 and NC. Only keep FSS
keep if PriceType == "FSS"

*Drop entries for generics 
drop if Generic == "generic"

*Merge in NDC/FFS units and divide FSS price (which is for the whole package) by the number of units
merge m:1 ndc_s11 using "ndcunits.dta"
drop if _m == 2
drop _m

*Get FSS price per unit
destring Price, replace
replace Price = Price / Finalunitsperpackage

*Check if there are obs where the price is listed as negative
list if Price < 0

*There are 2 NDCs where the FFS price is listed as -1 for 2013 Q3 and Q4. Use the average of 2013 Q2 and 2014 Q1 instead.
* 124961202 - average of 2.313 and 2.8306667 = 2.5718334
replace Price = 2.5718334 if ndc_s11 == "12496120203" & year == 2013 & inlist(quarter, 3, 4)

*124961208 - average of 4.1413333 + 5.254 = 4.6976667
replace Price = 4.6976667 if ndc_s11 == "12496120803" & year == 2013 & inlist(quarter, 3, 4)

*Collapse down to NDC-9
bys ndc_s9 year quarter: egen avg_FSS = mean(Price)

*Count NDC-11s per NDC-9
bys ndc_s9 year quarter: egen countndc = count(ndc_s11)
sort year quarter ndc_s11


*Check when the redASP for the average across NDC-9 is different than the NDC-11
replace Price = round(Price, 0.00001)
replace avg_FSS = round(avg_FSS, 0.00001)
count if Price != avg_FSS
*br ndc_s11 ndc_s9 Price avg_FSS countndc year quarter if Price != avg_FSS & countndc > 1 & year >= 2010

*Check how different it is
gen avgratio_FSS =  avg_FSS / Price
count if (avgratio_FSS < .8 | avgratio_FSS > 1.2) & countndc > 1 & year >= 2010

*Drop duplicates by NDC-9 within each year and quarter
duplicates drop ndc_s9 year quarter, force

*Only keep necessary variables
rename avg_FSS FSS_ndc9
keep FSS_ndc9 PriceStartDate PriceStopDate year quarter ndc_s9
save "fss.dta", replace



/****************************************************************
Read in Federal Supply Schedule units that were emailed to us from the FSS help account.
This shows the number of units for each price listed in the FSS data
Contact: Robert W. Cuvala <Robert.Cuvala@va.gov>
****************************************************************/
import excel using "${fss}/NDC list for FSS Research for M.Epstein_20191230.xlsx", firstrow clear

gen ndc_s1 = substr(NDC, 1, 5)
gen ndc_s2 = substr(NDC, 7, 4)
gen ndc_s3 = substr(NDC, 12, 2)

egen ndc_s9 = concat(ndc_s1 ndc_s2)
egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)

replace QtyofSale = "" if inlist(QtyofSale, "NOT ON CONTRACT", "Contract Cancelled")

*Sort by ndc 9 and then by QtsofSale so that if there is a duplicate NDC 9 and only one has quantity info, we keep that obs
gsort + ndc_s9 - QtyofSale
duplicates drop ndc_s9, force

keep ndc_s9 ndc_s11 QtyofSale

save "fssunits.dta", replace



