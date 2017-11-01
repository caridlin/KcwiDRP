;
; Copyright (c) 2017, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGESKY
;
; PURPOSE:
;	This procedure takes the output from KCWI_STAGE6RR and 
;	subtracts the sky.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGESKY, Procfname, Pparfname
;
; OPTIONAL INPUTS:
;	Procfname - input proc filename generated by KCWI_PREP
;			defaults to './redux/kcwi.proc'
;	Pparfname - input ppar filename generated by KCWI_PREP
;			defaults to './redux/kcwi.ppar'
;
; KEYWORDS:
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	KCWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	corresponding '*.proc' file in output directory to derive the list
;	of input files.  Each input file is read in and the required sky
;	is generated and subtracted from the observation.
;
; EXAMPLE:
;	Perform stagesky reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	KCWI_STAGESKY,'night1/redux/Sky.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2017-NOV-01	Initial version
;-
pro kcwi_stagesky,procfname,ppfname,help=help,verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGESKY'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Proc_filespec, Ppar_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = kcwi_read_ppar(ppfname)
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/nocreate) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; log file
	lgfil = reddir + 'kcwi_stagesky.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Filespec: '+ppar.filespec
	printf,ll,'Ppar file: '+ppfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; read proc file
	kpars = kcwi_read_proc(ppar,procfname,imgnum,count=nproc)
	;
	; gather configuration data on each observation in reddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; first check for response corrected data cube
		obfil = kcwi_get_imname(kpars[i],imgnum[i],'_icuber',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(kpars[i],imgnum[i],'_icubek',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check of output file exists already
			if kpars[i].clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				kcwi_print_cfgs,kcfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; report input file
				kcwi_print_info,ppar,pre,'input cube',obfil,format='(a,a)'
				;
				; are we an object file and not a nod-and-shuffle?
				do_sky = (1 eq 0)
				if kcfg.imgtype eq 'object' and kcfg.shuffmod eq 0 then begin
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; get wavelength info
					wave0 = sxpar(hdr,'crval3')
					dw = sxpar(hdr,'cd3_3')
					wave1 = wave0 + (sz[2]-1l) * dw
					;
					; log wavelength ranges
					kcwi_print_info,ppar,pre,'Input object   size, wavelength range', $
						sz[2],wave0,wave1,format='(a,i7,2f11.3)'
					;
					; read variance, mask images
					vfil = repstr(obfil,'_icube','_vcube')
					if file_test(vfil) then begin
						var = mrdfits(vfil,0,varhdr,/fscale,/silent)
					endif else begin
						var = fltarr(sz)
						var[0] = 1.	; give var value range
						varhdr = hdr
						kcwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
					endelse
					mfil = repstr(obfil,'_icube','_mcube')
					if file_test(mfil) then begin
						msk = mrdfits(mfil,0,mskhdr,/silent)
					endif else begin
						msk = intarr(sz)
						msk[0] = 1	; give mask value range
						mskhdr = hdr
						kcwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
					endelse
					;
					; do sky subraction
					kcwi_sub_sky,ppar,hdr,img,msk
					;
					; update header
					sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'SKYCOR','T',' sky corrected?'
					;
					; write out sky corrected mask image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_mcubek',/nodir)
					kcwi_write_image,msk,mskhdr,ofil,kpars[i]
					;
					; update header
					sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'SKYCOR','T',' sky corrected?'
					;
					; write out sky corrected variance image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_vcubek',/nodir)
					kcwi_write_image,var,varhdr,ofil,kpars[i]
					;
					; update header
					sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,hdr,'SKYCOR','T',' sky corrected?'
					;
					; write out sky corrected intensity image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_icubek',/nodir)
					kcwi_write_image,img,hdr,ofil,kpars[i]
					;
					; not an object file
				endif else begin
					if kcfg.imgtype eq 'object' then $
						kcwi_print_info,ppar,pre,'nod-and-shuffle obs, sky already subtracted' $
					else	kcwi_print_info,ppar,pre,'not an object file: '+kcfg.obsfname
				endelse
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if kpars[i].clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found, need icuber input: '+obfil,/warning
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	kcwi_print_info,ppar,pre,'run time in seconds',eltime
	kcwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end	; kcwi_stagesky
