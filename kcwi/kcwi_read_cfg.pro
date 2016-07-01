; $Id$
;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_READ_CFG
;
; PURPOSE:
;	This function reads the header from a KCWI image file and returns
;	a kcwi_cfg structure.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	Result = KCWI_READ_CFG( OBSFNAME )
;
; INPUTS:
;	obsfname- filename of KCWI image file
;
; KEYWORDS:
;	VERBOSE - set this to get extra screen output
;
; RETURNS:
;	KCWI CFG struct (as defined in kcwi_cfg__define.pro)
;
; PROCEDURE:
;	Reads in fits header and populates the KCWI_CFG struct.
;
; EXAMPLE:
;
;	This will read in the file 'm82.fits' and return a kcwi_cfg struct:
;
;	m82cfg = KCWI_READ_CFG('m82.fits')
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-03	Initial version
;	2014-SEP-12	Put in code to verify header
;-
function kcwi_read_cfg,obsfname,verbose=verbose
;
; initialize
	pre = 'KCWI_READ_CFG'
	A = {kcwi_cfg}		; get blank parameter struct
	cfg = struct_init(A)	; initialize it
;
; get filename if not passed as a parameter
	if n_params(0) lt 1 then begin
		obsfname = ''
		read,'Enter KCWI image FITS file name: ',obsfname
	endif
;
; check file
	fi = file_info(obsfname)
	if not fi.exists or not fi.read or not fi.regular then begin
		print,pre+': Error - file not accessible: ',obsfname
		return,cfg
	endif
;
; read header of KCWI image FITS file
	hdr = headfits(obsfname)
;
; verify header
	if size(hdr,/type) ne 7 or size(hdr,/dim) le 10 then begin
		print,pre+': Error - bad header: ',obsfname
		return,cfg
	endif
;
; get parameter struct tags
	keys = tag_names(cfg)
	nkeys = n_elements(keys)
	stopky = where(strcmp(keys,'JULIANDATE') eq 1)>0<nkeys
	stopky = stopky[0]
;
; get values for all native property keys
	for j=0, stopky-1 do begin
		val = sxpar(hdr,keys[j],count=nval)
		if nval eq 1 then $
			cfg.(j) = val
	endfor
;
; process the derived property keys
	ccdsum		= sxpar(hdr,'CCDSUM')
	cfg.xbinsize	= fix(gettok(ccdsum,' '))
	cfg.ybinsize	= fix(ccdsum)
	if cfg.xbinsize gt 1 or cfg.ybinsize gt 1 then $
		cfg.binning	= 1 $
	else	cfg.binning	= 0
	cfg.juliandate	= kcwi_parse_dates(cfg.datepclr)
	fdecomp,obsfname,disk,dir,root,ext
	cfg.date	= cfg.datepclr
	cfg.gratid	= cfg.bgratnam
	cfg.gratnum	= cfg.bgratnum
	cfg.grangle	= cfg.bgrangle
	cfg.grenc	= cfg.bgrenc
	cfg.filter	= cfg.bfiltnam
	cfg.filtnum	= cfg.bfiltnum
	cfg.campos	= cfg.bartenc
	cfg.camang	= cfg.bartang
	cfg.focpos	= cfg.bfocpos
	cfg.focus	= cfg.bfocus
	if cfg.bnaspos eq 2 then begin
		cfg.nasmask = 1
		cfg.nsskyr0 = 1
		cfg.nsskyr1 = cfg.shufrows
		cfg.nsobjr0 = cfg.nsskyr1 + 1
		cfg.nsobjr1 = cfg.nsobjr0 + cfg.shufrows
	endif else	cfg.nasmask = 0
	cfg.obsfname	= root + '.' + ext
	cfg.obsdir	= disk + dir
	cfg.obstype	= 'test'
	caltype		= strlowcase(strtrim(cfg.caltype,2))
	cfg.imgtype	= caltype
	if strcmp(caltype,'bias') eq 1 then begin
		cfg.obstype	= 'zero'
	endif else if strcmp(caltype,'dark') eq 1 then begin
		cfg.obstype	= 'zero'
	endif else if strcmp(caltype,'arcflat') eq 1 then begin
		cfg.imgtype	= 'arc'
		cfg.obstype	= 'cal'
	endif else if strcmp(caltype,'cbars') eq 1 then begin
		cfg.obstype	= 'cal'
	endif else if strcmp(caltype,'cflat') eq 1 then begin
		cfg.obstype	= 'cal'
	;
	; TODO: put in case for dome flats that checks for
	; object type and dome lamp on.
	endif else if strcmp(caltype,'object') eq 1 then begin
		cfg.obstype	= 'obj'
	endif
	cfg.imgnum	= long(stregex(root,'[0-9]+',/extract))
	cfg.initialized	= 1
	cfg.timestamp	= double(fi.mtime)	; use file timestamp
	return,cfg
end
