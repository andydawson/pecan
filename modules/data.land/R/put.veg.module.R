.put.veg.module <- function(getveg.id, bety, 
                            input_veg, pfts,
                            outfolder, 
                            dir, machine, model,
                            start_date, end_date,
                            lat, lon, site_id, 
                            host, overwrite){
  
  #--------------------------------------------------------------------------------------------------#
  # Read
  con <- bety$con
  spp.file <- db.query(paste("SELECT * from dbfiles where container_id =", getveg.id), con)
  rds_file <- file.path(spp.file$file_path, spp.file$file_name)
  veg_info <- readRDS(rds_file) 
  
  #--------------------------------------------------------------------------------------------------#
  # Match PFTs
  
  obs <- veg_info[[2]]
  
  pft.info <- match_pft(obs$bety_species_id, pfts, con)
  
  ### merge with other stuff
  obs <- cbind(obs, pft.info[c("bety_pft_id", "pft")])
  
  veg_info[[2]] <- obs 
  
  #--------------------------------------------------------------------------------------------------#
  # convert.inputs : write model specific IC files
  
  # Determine IC file format name and mimetype
  model_info <- db.query(paste0("SELECT f.name, f.id, mt.type_string from modeltypes as m", " join modeltypes_formats as mf on m.id = mf.modeltype_id", 
                                " join formats as f on mf.format_id = f.id", " join mimetypes as mt on f.mimetype_id = mt.id", 
                                " where m.name = '", model, "' AND mf.tag='", input_veg$output,"'"), con)
  
  logger.info("Begin Model Specific Conversion")
  
  formatname <- model_info[1]
  mimetype   <- model_info[3]
  
  print("Convert to model format")
  
  
  ## Set model-specific functions
  pkg <- paste0("PEcAn.", model)
  do.call("library", list(pkg))
  fcn <- paste("veg2model.", model, sep = "")
  if (!exists(fcn)) {
    logger.severe(paste(fcn, "does not exist."))
  }
  
  putveg.id <- convert.input(input.id = getveg.id,
                          outfolder = outfolder, 
                          formatname = formatname, 
                          mimetype = mimetype,
                          site.id = site_id, 
                          start_date = start_date, end_date = end_date, 
                          pkg = pkg, fcn = fcn, 
                          con = con, host = host, browndog = NULL, 
                          write = TRUE, 
                          overwrite = overwrite, 
                          # fcn specific args 
                          lat = lat, lon = lon,
                          # site.id is passed to convert.inputs but not passed to
                          # fcn.args within convert.inputs, where to fix it?
                          site_id = site_id, 
                          source = input_veg$source,
                          veg_info = veg_info)
  
  return(putveg.id)
  
}