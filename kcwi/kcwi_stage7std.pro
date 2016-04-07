; $Id$
;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE7STD
;
; PURPOSE:
;	This procedure uses a standard star observation to derive
;	a calibration of the related object data cubes.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE7STD, Pparfname, Linkfname
;
; OPTIONAL INPUTS:
;	Pparfname - input ppar filename generated by KCWI_PREP
;			defaults to './redux/kcwi.ppar'
;	Linkfname - input link filename generated by KCWI_PREP
;			defaults to './redux/kcwi.link'
;
; KEYWORDS:
;	SELECT	- set this keyword to select a specific image to process
;	PROC_IMGNUMS - set to the specific image numbers you want to process
;	PROC_STDNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_STDNUMS must have the same number of items
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
;	corresponding '*.link' file in output directory to derive the list
;	of input files and their associated std files.  Each input
;	file is read in and the required calibration is generated and 
;	applied to the observation.
;
; EXAMPLE:
;	Perform stage7std reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	KCWI_STAGE7STD,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-APR-22	Initial version
;	2014-MAY-13	Include calibration image numbers in headers
;	2014-SEP-23	Added extinction correction
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro kcwi_stage7std,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_stdnums=proc_stdnums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE7STD'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Ppar_filespec, Link_filespec'
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
	; specific images requested?
	if keyword_set(proc_imgnums) then begin
		nproc = n_elements(proc_imgnums)
		if n_elements(proc_stdnums) ne nproc then begin
			kcwi_print_info,ppar,pre,'Number of stds must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		snums = proc_stdnums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		kcwi_read_links,ppar,linkfname,imgnum,std=snums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			kcwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'kcwi_stage7std.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these stds : ',snums
	endif else $
		printf,ll,'Master link file: '+linkfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; gather configuration data on each observation in reddireddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; require output from kcwi_stage6rr
		obfil = kcwi_get_imname(ppar,imgnum[i],'_icuber',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(ppar,imgnum[i],'_icubes',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check if output file exists already
			if ppar.clobber eq 1 or not file_test(ofil) then begin
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
				; do we have a std link?
				do_std = (1 eq 0)
				if snums[i] ge 0 then begin
					;
					; master std file name
					stdf = kcwi_get_imname(ppar,snums[i],/nodir)
					;
					; corresponding master std file name
					msfile = cdir + strmid(stdf,0,strpos(stdf,'.fit'))+ '_invsens.fits'
					;
					; is std file already built?
					if file_test(msfile) then begin
						do_std = (1 eq 1)
						;
						; log that we got it
						kcwi_print_info,ppar,pre,'std file = '+msfile
					endif else begin
						;
						; does input std image exist?
						sinfile = kcwi_get_imname(ppar,snums[i],'_icuber',/reduced)
						if file_test(sinfile) then begin
							do_std = (1 eq 1)
							kcwi_print_info,ppar,pre,'building std file = '+msfile
						endif else begin
							;
							; log that we haven't got it
							kcwi_print_info,ppar,pre,'std input file not found: '+sinfile,/warning
						endelse
					endelse
				endif
				;
				; let's read in or create master std
				if do_std then begin
					;
					; build master std if necessary
					if not file_test(msfile) then begin
						;
						; get observation info
						scfg = kcwi_read_cfg(sinfile)
						;
						; build master std
						kcwi_make_std,scfg,ppar
					endif
					;
					; read in master std
					mstd = mrdfits(msfile,0,mshdr,/fscale,/silent)
					;
					; get dimensions
					mssz = size(mstd,/dimension)
					;
					; get master std waves
					msw0 = sxpar(mshdr,'crval1')
					msdw = sxpar(mshdr,'cdelt1')
					mswav = msw0 + findgen(mssz[0]) * msdw
					;
					; get master std image number
					msimgno = sxpar(mshdr,'IMGNUM')
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; get object waves
					w0 = sxpar(hdr,'crval3')
					dw = sxpar(hdr,'cd3_3')
					wav = w0 + findgen(sz[2]) * dw
					;
					; resample onto object waves, if needed
					if w0 ne msw0 or dw ne msdw or wav[sz[2]-1] ne mswav[mssz[0]-1] or $
						sz[2] ne mssz[0] then begin
						kcwi_print_info,ppar,pre, $
							'wavelengths scales not identical, resampling standard',/warn
						linterp,mswav,mstd,wav,mscal
					endif else mscal = mstd
					;
					; get exposure time
					expt = sxpar(hdr,'EXPTIME')
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
					; correct extinction
					kcwi_correct_extin,img,hdr,ppar
					;
					; do calibration
					for is=0,23 do begin
						for ix = 0, sz[0]-1 do begin
							img[ix,is,*] = (img[ix,is,*]/expt) * mscal
							;
							; convert variance to flux units (squared)
							var[ix,is,*] = (var[ix,is,*]/expt^2) * mscal^2
						endfor
					endfor
					;
					; update header
					sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'STDCOR','T',' std corrected?'
					sxaddpar,mskhdr,'MSFILE',msfile,' master std file applied'
					sxaddpar,mskhdr,'MSIMNO',msimgno,' master std image number'
					sxaddpar,mskhdr,'BUNIT','FLAM',' brightness units'
					;
					; write out mask image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_mcubes',/nodir)
					kcwi_write_image,msk,mskhdr,ofil,ppar
					;
					; update header
					sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'STDCOR','T',' std corrected?'
					sxaddpar,varhdr,'MSFILE',msfile,' master std file applied'
					sxaddpar,varhdr,'MSIMNO',msimgno,' master std image number'
					sxaddpar,varhdr,'BUNIT','FLAM',' brightness units'
					;
					; output variance image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_vcubes',/nodir)
					kcwi_write_image,var,varhdr,ofil,ppar
					;
					; update header
					sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,hdr,'STDCOR','T',' std corrected?'
					sxaddpar,hdr,'MSFILE',msfile,' master std file applied'
					sxaddpar,hdr,'MSIMNO',msimgno,' master std image number'
					sxaddpar,hdr,'BUNIT','FLAM',' brightness units'
					;
					; write out final intensity image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_icubes',/nodir)
					kcwi_write_image,img,hdr,ofil,ppar
					;
					; check for nod-and-shuffle sky image
					sfil = repstr(obfil,'_icube','_scube')
					if file_test(sfil) then begin
						sky = mrdfits(sfil,0,skyhdr,/fscale,/silent)
						;
						; correct extinction
						kcwi_correct_extin,sky,skyhdr,ppar
						;
						; do correction
						for is=0,23 do for ix = 0, sz[0]-1 do $
							sky[ix,is,*] = (sky[ix,is,*]/expt) * mscal
						;
						; update header
						sxaddpar,skyhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,skyhdr,'STDCOR','T',' std corrected?'
						sxaddpar,skyhdr,'MSFILE',msfile,' master std file applied'
						sxaddpar,skyhdr,'MSIMNO',msimgno,' master std image number'
						sxaddpar,skyhdr,'BUNIT','FLAM',' brightness units'
						;
						; write out final intensity image
						ofil = kcwi_get_imname(ppar,imgnum[i],'_scubes',/nodir)
						kcwi_write_image,sky,hdr,ofil,ppar
					endif
					;
					; check for nod-and-shuffle obj image
					nfil = repstr(obfil,'_icube','_ocube')
					if file_test(nfil) then begin
						obj = mrdfits(nfil,0,objhdr,/fscale,/silent)
						;
						; correct extinction
						kcwi_correct_extin,obj,objhdr,ppar
						;
						; do correction
						for is=0,23 do for ix = 0, sz[0]-1 do $
							obj[ix,is,*] = (obj[ix,is,*]/expt) * mscal
						;
						; update header
						sxaddpar,objhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,objhdr,'STDCOR','T',' std corrected?'
						sxaddpar,objhdr,'MSFILE',msfile,' master std file applied'
						sxaddpar,objhdr,'MSIMNO',msimgno,' master std image number'
						sxaddpar,objhdr,'BUNIT','FLAM',' brightness units'
						;
						; write out final intensity image
						ofil = kcwi_get_imname(ppar,imgnum[i],'_ocubes',/nodir)
						kcwi_write_image,obj,hdr,ofil,ppar
					endif
					;
					; handle the case when no std frames were taken
				endif else begin
					kcwi_print_info,ppar,pre,'cannot associate with any master std: '+ $
						kcfg.obsfname,/warning
				endelse
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if ppar.clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/warning
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
end
