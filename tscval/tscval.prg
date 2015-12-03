'Author: James Lamb, Abbott Economics

'Motivation: Perform rolling time-series corss validation.

'Description: 
' 	Program which takes an equation, rolls teh sample, keeps producing forecasts,
' 	then stacks up vectors by horizon and computes errors at different horizons.
' 	Returns a few objects in the wf:
'		1. T_ACC --> a table with the eq name and error (see below) by forecast horizon
'		2. V_{%eq}_{%ERR_MEASURE} --> a vector for the given equation, where element 1 is 1-step-ahead, elem 2 is 2-step, etc.

'##########################################################################################################
'##########################################################################################################
'##########################################################################################################
setmaxerrs 1
mode quiet
logmode logmsg
logmsg

'NOTE: Currently only supports equation objects (no VARs)
		
		!debug = 1 'set to 1 if you want the logmsgs to display
	
		if !debug = 0 then
			logmode +addin
		endif
		
		!dogui = 1 'Get data from the GUI
		
		'check that an object exists
		%type = @getthistype
		if %type="NONE" then
			@uiprompt("No object found, please open an Equation object")
			stop
		endif
		
		'check that {%eq} object is an equation
		if %type<>"EQUATION" then
			@uiprompt("Procedure can only be run from an Equation object")
			stop
		endif
		
		'Option 1 = the training range (from which many training samples will be drawn)
		if @len(@option(1)) > 0 then
			%training_range = @equaloption("TRAIN")
			logmsg --- longest sample %training_range
			!dogui = 0 'if we get here, it must mean that this is being run programmatically
		endif
		
		'Option 2 =  what % of the sample should we use to test?
		if @len(@option(1)) > 0 then
			!holdout = @val(@equaloption("H")) 'maximum % of the training range to forecast over
		endif

		'Option 3 = What error measure do you prefer?
		if @len(@option(3)) > 0 then
			%err_measure = @equaloption("ERR") 
		endif

		'Option 4 = Do you want to keep the forecast series objects?
		if @len(@option(4)) > 0 then
			!keep_fcst = @hasoption("T")
			!keep_fcst = @hasoption("TRUE")
		endif
		
		'--- Environment Info ---'
		%freq = @pagefreq 'page frequency
		%pagesmpl = @pagesmpl
		%pagename = @pagename
		%wf = @wfname
		%eq = _this.@name 'get the name of whatever we're using this on
		%command = {%eq}.@command 'command to re-estimate (with all the same options)
		
		'Grab a bit of information from the equation
		wfselect {%wf}\{%pagename}
		{%eq}.makeregs g1
		%base_dep = @word(g1.@depends,1) 'dependent variable WITHOUT transformations
		
		stomna(g1,m1)
		%first =  @otod(@min(@cifirst(m1)))
		%last = @otod(@min(@cilast(m1))) 'get the end of the longest estimable sample
		%training_range = %first + " " + %last
		delete g1

		'Set up the GUI
		if !dogui = 1 then
			!keep_fcst = 0
			%error_types = " ""MSE"" ""MAE"" ""RMSE"" ""MSFE"" ""MAPE"" ""SMAPE"" ""MPE"" ""MSPE"" ""RMSPE"" ""Correct sign (count)"" ""Correct sign (%)"" " 
			
			'Initialize with reasonable values
			%holdout = "0.10" 'default to testing over 10% of the training range
			%training_range = %training_range
			%err_measure = "MAE"
			!keep_fcst = 0
			
			!result = @uidialog("edit", %training_range, "Training range", "edit", %holdout, "Maximum % of the training range to hold out", _
			"list", %err_measure, "Preferred error measure", %error_types, "Check", !keep_fcst, "Keep the forecast series objects?" )
			
			!holdout = @val(%holdout)

		endif

		'Get params
		'---- Passed in ------'
'		%eq = {%0} 'equation object to work with
'		%short_end = {%1} 'end of the shortest sample to forecast over
'		%longest_smpl = {%2} 'What is the longest sample to estiamte? e.g. "1990 2015M10"
'		%err_measure = {%3} 'what error measure do you prefer? 
'			'Valid options:
''				a. "MSE" = mean squared error
''				b. "MAE" = mean absolute error
''				c. "RMSE" = root mean squuared error
''				d. "MSFE" = mean squared forecast error
''				e. "MAPE" = mean absolute percent error
''				f. "MPE" = mean percentage error
''				g. "MSPE" = mean squared percentage error
''				h. "RMSPE" = root mean squared percentage error
''				i. "SIGN" = count of the number of times the forecast guess the correct direction of change
''				j. "SIGN_PERCENT" = percent of the times that we guessed the sign of the forecast correctly
'				k. "SMAPE" = symmetric MAPE (see http://robjhyndman.com/hyndsight/smape/
'			
'		%keep_fcst = {%4} 'Set to "TRUE" or "T" to avoid deleting the forecast series
		
		!init_obs = @round( (1-!holdout) * (@dtoo(@word(%training_range,2)) - @dtoo(@word(%training_range,1))) ) + @dtoo(%first) 		
		%short_end = @otod(!init_obs)
			
		%start_est = @word(%training_range,1) 'where should estimation start?
		%end_est = @word(%training_range,2) 'where should the longest estimation end?
		!tot_eqs = @dtoo(%end_est) - @dtoo(%short_end) 'number of estimations we'll do
			
		%newpage = "TMPAAAAA" 'give it a ridiculous name to avoid overwriting stuff
		pagecreate(page={%newpage}) {%freq} {%pagesmpl} 'give it a crazy name to minimize risk of overwriting things
		wfselect {%wf}\{%newpage}
		
		'Create a group of regressors and copy it over
		'NOTE: This will take only the base series. If the reg. has CPI and d(CPI), only CPI is copied
		wfselect {%wf}\{%pagename}
		%rgroup = "g_blahblah"
		{%eq}.makeregs {%rgroup}
			{%rgroup}.drop @trend @trend^2 log(@trend)
		copy(g=d) {%pagename}\{%rgroup} {%newpage}\{%rgroup} '(g=d) --> series only (not the group object
		
		'delete that group
		delete {%pagename}\{%rgroup}
		
		copy {%pagename}\{%eq} {%newpage}\{%eq}
		wfselect {%wf}\{%newpage}
		
		'---- Date format ----'
		%freq = @pagefreq
	
		if %freq = "A" then 
			%date_format = "YYYY"
		else
			if %freq = "Q" then
				%date_format = "YYYY[Q]Q"
			else
				if %freq = "M" then
					%date_format = "YYYY[M]MM"
				else
					if @wfind("W D5 D7 D", %freq) <> 0 then
						%date_format = "MM/DD/YYYY"
					endif
				endif
			endif
		endif
		
		'Return this string in a workfile object
		string date_fmt = %date_format
		
		logmsg --- got past date format
		
	logmsg --- Beginning rolling estimation and forecasting
		
		for !i = 0 to !tot_eqs-1
			
			'Estimate the model for this sample
			%end_est = @datestr(@dateadd(@dateval(%short_end), +{!i}, %freq), date_fmt)
			%est_smpl = %start_est + " " + %end_est
			logmsg --- Estimating {%eq} over sample %est_smpl
			
			smpl {%est_smpl}
				{%eq}.{%command} 're-estimates the equation
				
			'Forecast over all the remaining periods
			%start_fcst = @datestr(@dateadd(@dateval(%end_est), +1, %freq), date_fmt)
			
			smpl {%start_fcst} @last
				{%eq}.forecast(f=na) {%base_dep}_f_{%start_fcst}
			smpl @all
		next
		logmsg --- got through all the rolling and forecasting
			
	logmsg --- Creating Series and Vectors of Errors
	
		%lookup = %base_dep + "_F_*"
		%list = @wlookup(%lookup, "series")
		for %series {%list}
			
			smpl @all
			
				%prefx = %base_dep + "_F_"
				
				'Absolute errors
				%error_ser = @replace(%series, %prefx, "ERR_")
				%error_vec = @replace(%series, %prefx, "V_ERR_")
				series {%error_ser} = {%base_dep} - {%series} 'prediction is always of the level, not the transformation!
				vector {%error_vec} = @convert({%error_ser})
				
				'Percentage errors
				%pc_error_ser = @replace(%series, %prefx, "ERR_PC_") 'percentage error
				%pc_error_vec = @replace(%series, %prefx, "V_PCERR_") 'percentage error
				series {%pc_error_ser} = 100*({%base_dep} - {%series})/({%base_dep}) 'report in percentage point units (thus the *100)
				vector {%pc_error_vec} = @convert({%pc_error_ser})
				
				'Sign errors
				%sign_error_ser = @replace(%series, %prefx, "ERR_SGN_") 'sign error
				%sign_error_vec = @replace(%series, %prefx, "V_SGNERR_") 'sign error
					'Get a series of changes for the denominator
					series changes = d({%base_dep})
					changes = @recode(changes=0, 1e-03, changes) 'recode 0s to small positive (want to treat  0 as positive)
					
					'If change in fcst and change in actual are in the same direction, the sign was correct
					series {%sign_error_ser} = (({%series}- {%base_dep}(-1)) / changes) > 0 '1 if correct sign, 0 otherwise
					vector {%sign_error_vec} = @convert({%sign_error_ser})
					
				'Sums for sMAPE (see http://robjhyndman.com/hyndsight/smape/)
				%sym_error_ser = @replace(%series, %prefx, "ERR_SYM_")
				%sym_error_vec = @replace(%series, %prefx, "V_SYMERR_")
				series {%sym_error_ser} = 2*@abs({%base_dep} - {%series})/(@abs({%base_dep}) + @abs({%series}))
				vector {%sym_error_vec} = @convert({%sym_error_ser})
	
			smpl @all
			
		next
		logmsg --- got through creating series and vectors of errors

	logmsg --- Collecting the n-step-ahead errors
		
		'Absolute errors
		%list = @wlookup("v_err_*", "vector")
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_vec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next
		
		'Percent errors
		%list = @wlookup("v_pcerr_*", "vector")
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_pcvec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next
		
		'Sign errors
		%list = @wlookup("v_sgnerr_*", "vector")
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_sgnvec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next
		
		'sMAPE errors
		%list = @wlookup("v_symerr_*", "vector")
		
		!stuff = @wcount(%list)
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_symvec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next
		
	logmsg --- Creating the Forecast Eval table
	
		table t_acc
		%err_vecs = @wlookup("e_vec_*", "vector")
		t_acc(1,3) = "STEPS AHEAD -->"
		t_acc(2,1) = "Model"
		t_acc(3,1) = %eq
		t_acc(3,2) = "Forecasts:"
		t_acc(4,1) = %eq
		%err_txt = %err_measure + ":"
		t_acc(4,2) = %err_txt
		for !col = 3 to (@wcount(%err_vecs)+2)
			
			'Assign a header to the table indicating how many steps ahead
			%head = @str(!col - 2)
			t_acc(2, !col) = %head
			
			'How many forecasts did we have at this horizon?
			%vec = "E_VEC_" + %head
			%pc_vec = "E_PCVEC_" + %head 'percentage errors
			%sign_vec = "E_SGNVEC_" + %head
			%sym_vec = "E_SYMVEC_" + %head
			!obs = @obs({%vec})
			t_acc(3, !col) = @str(!obs)
			
			'How did they do?
			
			'Absolute errors
			!MAE = @mean(@abs({%vec}))
			!MSE = @mean(@epow({%vec},2))
			!MSFE = !MSE  'some people use different terms
			!RMSE = @sqrt(!MSE)
			
			'Percentage errors
			!MAPE = @mean(@abs({%pc_vec}))
			!MPE = @mean({%pc_vec})
			!MSPE = @mean(@epow({%pc_vec},2))
			!RMSPE = @sqrt(!MSPE)
			!SMAPE = @mean({%sym_vec})
			
			'Sign Errors
			!SIGN = @sum({%sign_vec})
			!SIGN_PERCENT = 100*(!SIGN/@obs({%sign_vec}))
			
			t_acc(4,!col) =!{%err_measure}
		next
		!cols = @columns(t_acc)
		t_acc.setformat(R3C3:R4C{!cols}) f.3 'only display three decimal places
		t_acc.setlines(R2C1:R2C{!cols}) +b 'underline the header row
		
		show t_acc
	
	logmsg --- Cleaning up intermediate forecasting variables
	
		wfselect {%wf}\{%newpage}
		delete e_vec_* date_fmt* err_* v_err_* *obsid* e_pc* *sgn* *_pcerr_* *tmp* changes* *sym*
		
		if !keep_fcst <> 1 then
			delete {%base_dep}_f_*
		endif
		
	logmsg --- Creating a single vector of errors
	
		'Element 1 will be 1-step-ahead MSE, element 2 will be 2-step-ahead-MSE, etc.
		!steps = @columns(t_acc) - 2
		vector(!steps) v_{%eq}_{%err_measure} = NA
		for !col = 3 to (!steps + 2)
			!indx = !col - 2
			v_{%eq}_{%err_measure}(!indx) = @val(t_acc(4,!col)) 'errors always in row 4
		next
	
	logmsg --- Move everything left back over to the original page
	
		copy {%newpage}\t_acc {%pagename}\t_acc
		copy {%newpage}\v_* {%pagename}\v_*
		pagedelete {%newpage}
		wfselect {%wf}\{%pagename}
		
		'if this was run from the GUI (on one equation), show the table of results
		if !dogui = 1 then
			show t_acc
		endif
		
	logmsg
	logmsg ------ TSCVAL COMPLETE ------
	logmsg
		
'##########################################################################################################
'##########################################################################################################
'##########################################################################################################
'===========================================References===================================================='
'
'1. http://faculty.smu.edu/tfomby/eco5385/lecture/Scoring%20Measures%20for%20Prediction%20Problems.pdf
'2. http://robjhyndman.com/hyndsight/tscvexample/
'3. http://robjhyndman.com/hyndsight/crossvalidation/
'4. http://robjhyndman.com/hyndsight/smape/
'5. http://robjhyndman.com/papers/foresight.pdf


