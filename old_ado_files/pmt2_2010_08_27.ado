program define pmt2, rclass
	// July 26 2010
	// July 31 2010 - this routine uses the pmt_eligible.ado program. I've split this into two, incase one wishes to evaluate the performance of non-regression models
	// August 03 2010 : I want to replace the sum command with one that uses survey settings. This works well. Next one will add option to use betas from
	//					a subsample to predict consumption for the rest of the sample
	// August 04 2010 : Adding option to use betas from a subsample. STILL NEED TO VERIFY THAT IT IS WORKING PROPERLY. Also removing reduncancy for pmt_eligible in having to specifiy the Quantiles variable AND the number of Quantiles.
	// August 06 2010 : For threshold, will use bottom X percent of ACTUAL (not predicted) consumption of the ENTIRE sample
	
	syntax varlist(min=2 ts) [if] [pw aw iw fw], Cutoffs(numlist asc min=1 max=20 >0 <=50 integer) Poor(varname numeric) Quantiles(integer) [Graphme(integer -1) logpline(real 0) Usesubsamplebetas(varname numeric)]
	version 9.1 
	marksample touse
	
	// Need to get the weights, so that I can use this with the _pctile command below.
	qui svyset
	local svyweight = r(wtype)
	local svyexp    = r(wexp) 
	di "[`svyweight'`svyexp']"
	
	// Was the option to use betas from a subsample specified?
	if ( "`usesubsamplebetas'"=="") {
		// di "usesubsamplebetas NOT specified"
		tempvar usesubsamplebetas
		qui gen `usesubsamplebetas' = 1
		qui sum `usesubsamplebetas'
	} 
	
	tempvar logpccd_predicted logpccd_predicted_threshold 
	
	qui spearman `varlist' `if'
	return scalar rho = r(rho) 
	
	svy : reg `varlist' if `touse' & `usesubsamplebetas'==1	
	local R2 = e(r2) 
	local N = e(N)
	return scalar r2 = `R2'
	return scalar N = `N'
	// predict for the entire sample
	predict `logpccd_predicted' 
	qui count if `logpccd_predicted' ~= .
	qui local count_predicted = r(N)
	 	 
	foreach x of numlist `cutoffs' { // loop over all the cutoffs to be used
		
		// We are going to use cutoff of bottom X percent of ACTUAL consumption for the ENTIRE population
		
		_pctile `1' [`svyweight'`svyexp'], n(100)
			
		// return list
		local logcutoff = r(r`x')
		di "cutoff: `logcutoff'"
		
		tempvar eligible nonpoor_ineligible poor_ineligible nonpoor_eligible poor_eligible Quantilec
					
		qui gen `eligible' =.
		qui gen `nonpoor_eligible' = .
		qui gen `poor_ineligible' = .
		
		qui replace `eligible' = 1 if `logpccd_predicted' < `logcutoff' & `logpccd_predicted' ~= .  & `touse'
		qui replace `eligible' = 0 if `logpccd_predicted' >= `logcutoff' & `logpccd_predicted' ~= .  & `touse'
		
		qui replace `nonpoor_eligible' = 1 if `eligible' == 1 & `poor' ~= 1 & `poor' ~= . & `touse' 
		qui replace `nonpoor_eligible' = 0 if (`eligible' ~= 1 | `poor' == 1) & `touse'
		
		qui replace `poor_ineligible' = 1 if `eligible' == 0 & `poor' == 1 & `poor' ~= . & `touse' 
		qui replace `poor_ineligible' = 0 if (`eligible' == 1 | `poor' == 0) & `poor' ~= . & `touse' 
		
		qui gen `nonpoor_ineligible' =.
		replace `nonpoor_ineligible' = 1 if `poor'==0 & `eligible'==0 & `touse'
		replace `nonpoor_ineligible' = 0 if (`poor'==1 | `eligible'==1) & `touse'
		qui gen `poor_eligible'  =.
		replace `poor_eligible' = 1 if `poor'==1 & `eligible'==1 & `touse'
		replace `poor_eligible' = 0 if (`poor'==0 | `eligible'==0) & `touse'
		
		// what percent of the population is covered?
		qui svy : mean `eligible' if `touse'
		local percentofpop_covered = _coef[`eligible']
		return scalar percentofpop_covered_`x' = `percentofpop_covered'
		
		// First generate quantile indicators
		
		// Here the classification of quantile is done based on the entire sample. This is probably what most people want.
		qui xtile `Quantilec' = `1' [`svyweight'`svyexp'], n(`quantiles') 
				
		// [`weight'`exp'] is not used, but the darn thing doesn't work unless I include it!
		pmt_eligible `eligible' [`svyweight'`svyexp'], p(`poor') qu(`Quantilec')
		
		// Need to store the results somewhere, somehow
		return scalar leakage_`x' = r(leakage)
		return scalar undercoverage_`x' = r(undercoverage)
		forv q = 1/`quantiles' {
			return scalar coverage_cutoff`x'_quantile`q' = r(coverage_cutoff_quantile`q')
			local temp = r(coverage_cutoff_quantile`q')
			// di "scalar coverage_cutoff`x'_quantile`q' = `temp'"
		}
		
		if (`x'==`graphme')  {
			twoway (scatter `logpccd_predicted' `1' if `poor_ineligible'==1, xline(`logpline', lcolor(0)) yline(`logcutoff') mc(red) m(x) ) /* 
			*/	(scatter `logpccd_predicted' `1' if `nonpoor_ineligible' == 1, mc(green) m(x)) /*
			*/	(scatter `logpccd_predicted' `1' if `nonpoor_eligible'==1, mc(black) m(x)) /* (scatter `logpccd_predicted' `1' if `Quantilec'==10 & logpccd_predicted < `logcutoff' & `1' ~= . & `logpccd_predicted' ~= ., mc(blue) m(Oh))
			*/	 /*
			*/	(scatter `logpccd_predicted' `1' if `poor_eligible' == 1, mc(blue) m(x) xlabel(3(1)8) ylabel(3(1)8) ysc(r(3 8)) xsc(r(3 8)) ) /*
			*/ , title("Cutoff `x' pctile (TJK 2009)") legend(lab(1 "Errors of Exclusion") lab(3 "Errors of Inclusion") lab(2 "Nonpoor, Ineligible") lab(4 "Poor Eligible") )
		}
		
	}	
end program

