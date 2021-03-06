;
; Copyright (c) 2017, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE4FLAT
;
; PURPOSE:
;	This procedure generates and applies an illumination correction
;	to the input 2D image.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE4FLAT, Procfname, Pparfname
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
;	of input files and their associated master flat files.  Each input
;	file is read in and the required master flat is generated and 
;	fit and multiplied.  If the input image is a nod-and-shuffle
;	observation, the image is sky subtracted and then the flat is applied.
;
; EXAMPLE:
;	Perform stage4flat reductions on the images in 'night1' directory and put
;	results in 'night1/redux':
;
;	KCWI_STAGE4FLAT,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2017-NOV-13	Initial version
;-
pro kcwi_stage4flat,procfname,ppfname,help=help,verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE4FLAT'
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
	lgfil = reddir + 'kcwi_stage4flat.log'
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
	printf,ll,'Display level     : ',ppar.display
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
		; check for dark subtracted image first
		obfil = kcwi_get_imname(kpars[i],imgnum[i],'_intd',/reduced)
		;
		; if not just get stage1 output image
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(kpars[i],imgnum[i],'_int',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(kpars[i],imgnum[i],'_intf',/reduced)
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
				kcwi_print_info,ppar,pre,'input reduced image',obfil,format='(a,a)'
				;
				; read in image
				img = mrdfits(obfil,0,hdr,/fscale,/silent)
				;
				; get dimensions
				sz = size(img,/dimension)
				;
				; read variance, mask images
				vfil = repstr(obfil,'_int','_var')
				if file_test(vfil) then begin
					var = mrdfits(vfil,0,varhdr,/fscale,/silent)
				endif else begin
					var = fltarr(sz)
					var[0] = 1.	; give var value range
					varhdr = hdr
					kcwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
				endelse
				mfil = repstr(obfil,'_int','_msk')
				if file_test(mfil) then begin
					msk = mrdfits(mfil,0,mskhdr,/silent)
				endif else begin
					msk = intarr(sz)
					msk[0] = 1	; give mask value range
					mskhdr = hdr
					kcwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
				endelse
				;
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				; STAGE 4: FLAT CORRECTION
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				;
				; do we have a master flat file and geometry solution?
				do_flat = (1 eq 0)	; assume no to begin with
				if strtrim(kpars[i].masterflat,2) ne '' and $
				   strtrim(kpars[i].geomcbar,2) ne '' then begin
					;
					; master flat file name
					mffile = kpars[i].masterflat
					;
					; master flat image ppar filename
					mfppfn = repstr(mffile,'.fits','.ppar')
					;
					; geom file
					gfile = repstr(strtrim(kpars[i].geomcbar,2),'_int','_geom')
					;
					; check access
					if file_test(mfppfn) and file_test(gfile) then begin
						;
						; check status
						kgeom = mrdfits(gfile,1,/silent)
						if kgeom.status eq 0 then begin
							do_flat = (1 eq 1)
							;
							; log that we got it
							kcwi_print_info,ppar,pre,'flat file = '+mffile
							kcwi_print_info,ppar,pre,'geom file = '+gfile
						endif else begin
							kcwi_print_info,ppar,pre,'bad geometry solution in ',gfile, $
								format='(a,a)',/error
						endelse
					endif else begin
						;
						; log that we haven't got it
						if not file_test(mfppfn) then $
							kcwi_print_info,ppar,pre,'flat file not found: '+mffile,/error
						if not file_test(gfile) then $
							kcwi_print_info,ppar,pre,'geom file not found: '+gfile,/error
					endelse
				endif
				;
				; let's read in or create master flat
				if do_flat then begin
					;
					; skip flat correction for darks, continuum bars, and arcs
					if strpos(kcfg.imgtype,'bar') ge 0 or $
					   strpos(kcfg.imgtype,'arc') ge 0 or $
					   strpos(kcfg.imgtype,'dark') ge 0 or $
					   strpos(kcfg.obstype,'direct') ge 0 then begin
						kcwi_print_info,ppar,pre,'skipping flattening of dark/arc/bars/direct image',/info
					;
					; do the flat for science images
					endif else begin
						;
						; build master flat if necessary
						if not file_test(mffile) then begin
							;
							; build master flat
							fpar = kcwi_read_ppar(mfppfn)
							fpar.loglun    = kpars[i].loglun
							fpar.verbose   = kpars[i].verbose
							fpar.display   = kpars[i].display
							fpar.saveplots = kpars[i].saveplots
							kcwi_make_flat,fpar,gfile
						endif
						;
						; read in master flat image
						mflat = mrdfits(mffile,0,mfhdr,/fscale,/silent)
						;
						; read in master mask image
						mmfile = repstr(mffile,'_mflat','_mfmsk')
						mfmsk = mrdfits(mmfile,0,mmhdr,/silent)
						;
						; do correction
						img = img * mflat
						;
						; variance is multiplied by flat squared
						var = var * mflat^2
						;
						; mask combined with master flat
						msk += mfmsk
						;
						; get map files
						wmf = sxpar(mfhdr,'WAVMAPF',count=nmf)
						if nmf le 0 then $
							wmf = ''
						slf = sxpar(mfhdr,'SLIMAPF',count=nmf)
						if nmf le 0 then $
							slf = ''
						pof = sxpar(mfhdr,'POSMAPF',count=nmf)
						if nmf le 0 then $
							pof = ''
						;
						; update header
						fdecomp,mffile,disk,dir,root,ext
						sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,mskhdr,'FLATCOR','T',' flat corrected?'
						sxaddpar,mskhdr,'MFFILE',root+'.'+ext,' master flat file applied'
						sxaddpar,mskhdr,'WAVMAPF',wmf,' Wavemap file'
						sxaddpar,mskhdr,'SLIMAPF',slf,' Slicemap file'
						sxaddpar,mskhdr,'POSMAPF',pof,' Posmap file'
						;
						; write out flat corrected mask image
						ofil = kcwi_get_imname(kpars[i],imgnum[i],'_mskf',/nodir)
						kcwi_write_image,msk,mskhdr,ofil,kpars[i]
						;
						; update header
						sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,varhdr,'FLATCOR','T',' flat corrected?'
						sxaddpar,varhdr,'MFFILE',root+'.'+ext,' master flat file applied'
						sxaddpar,varhdr,'WAVMAPF',wmf,' Wavemap file'
						sxaddpar,varhdr,'SLIMAPF',slf,' Slicemap file'
						sxaddpar,varhdr,'POSMAPF',pof,' Posmap file'
						;
						; write out flat corrected variance image
						ofil = kcwi_get_imname(kpars[i],imgnum[i],'_varf',/nodir)
						kcwi_write_image,var,varhdr,ofil,kpars[i]
						;
						; update header
						sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,hdr,'FLATCOR','T',' flat corrected?'
						sxaddpar,hdr,'MFFILE',root+'.'+ext,' master flat file applied'
						sxaddpar,hdr,'WAVMAPF',wmf,' Wavemap file'
						sxaddpar,hdr,'SLIMAPF',slf,' Slicemap file'
						sxaddpar,hdr,'POSMAPF',pof,' Posmap file'
						;
						; write out flat corrected intensity image
						ofil = kcwi_get_imname(kpars[i],imgnum[i],'_intf',/nodir)
						kcwi_write_image,img,hdr,ofil,kpars[i]
					endelse
					;
					; handle the case when no flat frames were taken
				endif else $
					kcwi_print_info,ppar,pre,'cannot associate with any viable master flat: '+ $
							kcfg.obsfname,/warning
				flush,ll
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
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/error
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
end	; kcwi_stage4flat
