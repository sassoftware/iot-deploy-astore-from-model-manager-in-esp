Copyright © 2020, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
SPDX-License-Identifier: Apache-2.0


/** Connect to CAS **/
%let cashost=<your cashost>;
%let casport=<your casport, ex 5570>;
options cashost="&cashost." casport=&casport. ;
CAS casauto SESSOPTS=(CASLIB=public TIMEOUT=99 LOCALE="en_US");
libname mycas CAS ;

/*******************************************************************************************/
/**** 							Section 1: Data Preparation								****/
/****  Select the first 25% of observations that belong to 18 randomly selected engines ****/
/*******************************************************************************************/

data eng_subset; 
set mycas.turbofan_18eng;
by  Engine_ID datetime;
run;


/** Get count of rows for first 25% of obs (normal data) from 18 engines **/
proc sql;
create table sum_eng as
select Engine_ID as engine, count(Engine_ID) as nobs_engine, round(count(Engine_ID)*0.25) as top_25
from eng_subset
group by Engine_id;
quit;

data _null_; 
set sum_eng end=end;
count+1;
call symputx('engine'||'_'||left(count),engine);
call symputx('nobs'||'_'||left(count),nobs_engine);
call symputx('top_25'||'_'||left(count),top_25);

if end then call symputx('max',count);
run;

%put Count of engines: &max;

/** Create training data **/
%macro top_25;

%do i=1 %to &max.;

data turbofan_&i.; 
set eng_subset (obs=&&top_25_&i.);
where strip(Engine_ID)= strip("&&engine_&i.") ;
run;

%end;

data turbofan_training; 
set  %do i=1 %to &max. ; 
	turbofan_&i.
	%end ;
;
run;

data mycas.turbofan_training;
set turbofan_training;
run;

%mend;
%top_25;


/*******************************************************************************************/
/**** 							Section 2: Model Development							****/
/*******************************************************************************************/
/**** 		 Model 1- Select Vector Data Description (SVDD) for Anaomaly detection 		****/
/*******************************************************************************************/


Proc contents data=mycas.turbofan_training out= contents noprint varnum; run;
proc sql;
	select name into :varlist separated by ' ' from contents where type = 1;
quit;

%put &varlist.;

/* Phase 1: Train SVDD model using normal operations data from 18 engines */
proc svdd data=mycas.turbofan_training ;
    id engine_id Datetime;
    input &varlist/level=interval;
    kernel rbf / bw=trace(nrep=4);
  code file='/mnt/viya-share/homes/svdd_ds_scr.sas';
    savestate rstore=mycas.turbofan_svdd;
 run;                                    

/* Phase 2: Score rest of the 200 engines to get distance value to monitor degradation */
 proc astore;
    score data=mycas.turbofan_200eng
    out=mycas.svdd_out
    rstore=mycas.turbofan_svdd;
 quit;

/* Promote tables to global caslib to visualize in VA */
proc casutil;
  promote casdata="turbofan_training";
run;

