#!/usr/bin/env Rscript
#-------------------------------------------------------------------------------
# Copyright (c) 2012 University of Illinois, NCSA.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the 
# University of Illinois/NCSA Open Source License
# which accompanies this distribution, and is available at
# http://opensource.ncsa.illinois.edu/license.html
#-------------------------------------------------------------------------------

# ----------------------------------------------------------------------
# Load required libraries
# ----------------------------------------------------------------------
library(PEcAn.all)
library(PEcAn.utils)
library(RCurl)

# make sure always to call status.end
options(warn=1)
options(error=quote({
  status.end("ERROR")
  kill.tunnel(settings)
  if (!interactive()) {
    q()
  }
}))

#options(warning.expression=status.end("ERROR"))


# ----------------------------------------------------------------------
# PEcAn Workflow
# ----------------------------------------------------------------------
# Open and read in settings file for PEcAn run.
args <- commandArgs(trailingOnly = TRUE)
if (is.na(args[1])){
  settings <- PEcAn.settings::read.settings("pecan.xml")
} else {
  settings.file = args[1]
  settings <- PEcAn.settings::read.settings(settings.file)
}

# Check for additional modules that will require adding settings
if("benchmarking" %in% names(settings)){
  library(PEcAn.benchmark)
  settings <- papply(settings, read_settings_RR)
}

# Update/fix/check settings. Will only run the first time it's called, unless force=TRUE
settings <- PEcAn.settings::prepare.settings(settings, force=FALSE)

# Write pecan.CHECKED.xml
PEcAn.settings::write.settings(settings, outputfile = "pecan.CHECKED.xml")

# start from scratch if no continue is passed in
statusFile <- file.path(settings$outdir, "STATUS")
if (length(which(commandArgs() == "--continue")) == 0 && file.exists(statusFile)) {
  file.remove(statusFile)
}
  
# Do conversions
settings <- do.conversions(settings)


# Query the trait database for data and priors
if (status.check("TRAIT") == 0){
  status.start("TRAIT")
  settings <- runModule.get.trait.data(settings)
  PEcAn.settings::write.settings(settings, outputfile='pecan.TRAIT.xml')
  status.end()
} else if (file.exists(file.path(settings$outdir, 'pecan.TRAIT.xml'))) {
  settings <- PEcAn.settings::read.settings(file.path(settings$outdir, 'pecan.TRAIT.xml'))
}

  
# Run the PEcAn meta.analysis
if(!is.null(settings$meta.analysis)) {
  if (status.check("META") == 0){
    status.start("META")
    runModule.run.meta.analysis(settings)
    status.end()
  }
}
  
# Write model specific configs
if (status.check("CONFIG") == 0){
  status.start("CONFIG")
  settings <- runModule.run.write.configs(settings)
  PEcAn.settings::write.settings(settings, outputfile='pecan.CONFIGS.xml')
  status.end()
} else if (file.exists(file.path(settings$outdir, 'pecan.CONFIGS.xml'))) {
  settings <- PEcAn.settings::read.settings(file.path(settings$outdir, 'pecan.CONFIGS.xml'))
}
    
if ((length(which(commandArgs() == "--advanced")) != 0) && (status.check("ADVANCED") == 0)) {
  status.start("ADVANCED")
  q();
}

# Start ecosystem model runs
if (status.check("MODEL") == 0) {
  status.start("MODEL")
  runModule.start.model.runs(settings)
  status.end()
}

# Get results of model runs
if (status.check("OUTPUT") == 0) {
  status.start("OUTPUT")
  runModule.get.results(settings)
  status.end()
}

# Run ensemble analysis on model output. 
if ('ensemble' %in% names(settings) & status.check("ENSEMBLE") == 0) {
  status.start("ENSEMBLE")
  runModule.run.ensemble.analysis(settings, TRUE)    
  status.end()
}

# Run sensitivity analysis and variance decomposition on model output
if ('sensitivity.analysis' %in% names(settings) & status.check("SENSITIVITY") == 0) {
  status.start("SENSITIVITY")
  runModule.run.sensitivity.analysis(settings)
  status.end()
}

# Run parameter data assimilation
if ('assim.batch' %in% names(settings)) {
  if (status.check("PDA") == 0) {
    status.start("PDA")
    settings <- PEcAn.assim.batch::runModule.assim.batch(settings)
    status.end()
  }
}

# Run state data assimilation
if ('state.data.assimilation' %in% names(settings)) {
  if (status.check("SDA") == 0) {
    status.start("SDA")
    settings <- sda.enfk(settings)
    status.end()
  }
}

# Run benchmarking
if("benchmarking" %in% names(settings)){
  status.start("BENCHMARKING")
  results <- papply(settings, function(x) calc_benchmark(x, bety))
  status.end()
}
  
# Pecan workflow complete
if (status.check("FINISHED") == 0) {
  status.start("FINISHED")
  kill.tunnel(settings)
  db.query(paste("UPDATE workflows SET finished_at=NOW() WHERE id=", settings$workflow$id, "AND finished_at IS NULL"), params=settings$database$bety)

  # Send email if configured
  if (!is.null(settings$email) && !is.null(settings$email$to) && (settings$email$to != "")) {
    sendmail(settings$email$from, settings$email$to,
             paste0("Workflow has finished executing at ", base::date()),
             paste0("You can find the results on ", settings$email$url))
  }
  status.end()
}

db.print.connections()
print("---------- PEcAn Workflow Complete ----------")
