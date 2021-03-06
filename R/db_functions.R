##' Add table to the database
##'
##' PITA, microcosm and targetscan data for Mm were downloaded from
##' \url{http://genie.weizmann.ac.il/pubs/mir07/catalogs/PITA_targets_mm9_0_0_TOP.tab.gz}
##' \url{ftp://ftp.ebi.ac.uk/pub/databases/microcosm/v5/arch.v5.gff.mus_musculus.zip}
##' \url{http://www.targetscan.org//mmu_60//mmu_60_data_download/Conserved_Site_Context_Scores.txt.zip}
##' @export
##' @title add table to the database
##' @param file file and path 
##' @param tableName  either "pita", "microcosm", "targetscan"
##' @param dbName database name
##' @param path directory where database should be stored
##' @param parser user-defined parser function
##' @param Org organism use abbreviation e.g. Mm and Hs
##' @return NULL
##' @author Maarten
addTable <- function(file, tableName=c("pita", "microcosm", "targetscan"), parser = function(file, Org) stop("Parser not defined!"), dbName, path, Org=c("Mm", "Hs"))
  {
    ##create or connect to the database
    m <- dbDriver("SQLite")                  
    con <- dbConnect(m, dbname=file.path(path, dbName))

    ##prediction database specific
    cat("Reading ", file, ": ", sep="")    
    data <- switch(tableName,
                   pita = pita(file, Org),
                   microcosm = microcosm(file, Org),
                   targetscan = targetscan(file, Org),
                   parser(file, Org))

    cat("selected", nrow(data), "rows.\n")  
       
    returned <- dbWriteTable(con, tableName, data, overwrite=TRUE) 
    
    if(returned) 
      cat(paste(tableName, "table added succesfully.\n")) 
    else 
      cat("PROBLEM OCCURED!.\n")            
		 
    fieldNames <- dbListFields(con, tableName) 
    cat("\nTable contains fields: ", fieldNames, ".\n")
    
    invisible(dbDisconnect(con))        #close connection to database 
  }

##' Head of the database table, similar to head function.
##'
##' Details follow.
##' 
##' @title Head
##' @param dbName database name
##' @param table table name
##' @param path path to database
##' @param n number of lines
##' @return head of table
##' @author Maarten van Iterson
##' @export
dbHeadTable <- function(path, dbName, table, n=6)
{      
  m <- dbDriver("SQLite")               # simple sql request of scores
  con <- dbConnect(m, file.path(path, dbName))
  query <- paste("SELECT * FROM ", table, sep="")                
  rs <- dbGetQuery(con, query)
  invisible(dbDisconnect(con))          #close connection to database
  if(n==-1)
    n <- nrow(rs)
  rs[1:n,]
}

##' Gives some info of tables and fields of the database.
##'
##' Details follow.
##' 
##' @title Info
##' @param dbName database name
##' @param path path to database
##' @return info
##' @author Maarten van Iterson
##' @export
dbInfo <- function(path, dbName)
{
  m <- dbDriver("SQLite")             # simple sql request of scores
  con <- dbConnect(m, file.path(path, dbName))
  tables <- dbListTables(con)
  print(tables)
  fields <- sapply(tables, function(x) dbListFields(con, x))
  print(fields)	
  invisible(dbDisconnect(con))          #close connection to database
}

##' function to get all unique mirs from in the database.
##'
##' Details follow.
##' 
##' @title Unique mirs
##' @param path path to database
##' @param dbName database name
##' @return vector of all unique mirs
##' @author Maarten van Iterson, Sander Bervoets
##' @export
uniqueMirs<- function(path, dbName)
{      
  m <- dbDriver("SQLite")               # simple sql request of scores
  con <- dbConnect(m, file.path(path, dbName))
    
  mirs <- as.character()
  for(table in dbListTables(con))
    {
      print(table)
      query <- paste("SELECT DISTINCT miRNA FROM ", table," ", sep="") 
      mirs <- c(mirs, dbGetQuery(con, query)$miRNA)
    }
  
  invisible(dbDisconnect(con))          #close connection
  
  mirs[!duplicated(mirs)]
}

##' function to get all unique targets for a specific mir.
##'
##' Details follow.
##' 
##' @title Unique mirs
##' @param path path to database
##' @param dbName database name
##' @param mir microRNA for which unique targets will be obtained
##' @param tables NULL or one or more table names in the database
##' @return vector of unique targets
##' @author Maarten van Iterson, Sander Bervoets
##' @export
uniqueTargets <- function(path, dbName, mir, tables=NULL)
{      
  m <- dbDriver("SQLite")               # simple sql request of scores
  con <- dbConnect(m, file.path(path, dbName))
    
  if(missing(tables))
    tables <- dbListTables(con)
  
  targets <- as.character()
  for(table in tables)
    {
      query <- paste("SELECT DISTINCT mRNA FROM ", table, " WHERE miRNA = '", mir, "' ", sep="")      
      x <- dbGetQuery(con, query)$mRNA                

      targets <- c(targets, x)
    }
  
  invisible(dbDisconnect(con))          #close connection
  
  targets <- targets[!duplicated(targets)]
  ##targets[!is.na(targets)]
  targets
}


##' Determine overlapping targets between prediction tools
##'
##' Details follows
##' @title overlapping targets
##' @param path path to database
##' @param dbName database name
##' @param tables tables in the database
##' @param mir microRNA identifier
##' @param numOverlapping number of at least overlapping targets
##' @param full return full overlapping table or reduced only overlap  
##' @return matrix with overlapping targets
##' @author Maarten van Iterson
##' @export
overlap <- function(path, dbName, tables=NULL, mir, numOverlapping=2, full=TRUE)
  {    
    m <- dbDriver("SQLite")             # simple sql request of scores
    con <- dbConnect(m, file.path(path, dbName))

    if(is.null(tables))
      tables <- dbListTables(con)
    
    uTargets <- uniqueTargets(path, dbName, mir)
    
    overlappingTargets <- matrix(FALSE, nrow=length(uTargets), ncol=length(tables))
    
    for(i in 1:length(tables))
      {
        targets <- uniqueTargets(path, dbName, mir, tables[i])
        overlappingTargets[,i] <- uTargets %in% targets 
      }
   
    invisible(dbDisconnect(con))        #close connection
    
    colnames(overlappingTargets) <- tables
    rownames(overlappingTargets) <- uTargets    

    if(!full)
      overlappingTargets <- overlappingTargets[apply(overlappingTargets, 1, sum) >= numOverlapping, , drop=FALSE] #drop=FALSE in case one row left
    
    if(!any(apply(overlappingTargets, 1, sum) >= numOverlapping))
      {
      cat(paste(mir, " has no overlapping targets between the tables: ", paste(tables, collapse=", ", sep=""), "! ...\n", sep=""))
      return(NULL)
    }
    cat(paste(mir, " has ", nrow(overlappingTargets), " overlapping targets between the tables: ",  paste(tables, collapse=", ", sep=""), "! ...\n", sep=""))
    
    overlappingTargets    
  }

##' Find unique microRNAs
##'
##' Details will follow
##' @title Find unique microRNAs
##' @param path to database
##' @param dbName database name
##' @param target specific target
##' @param tables tables in the database
##' @return unique microRNAs
##' @author Maarten van Iterson
uniqueMirs_new <- function(path, dbName, target, tables=NULL)
{      
  m <- dbDriver("SQLite")               # simple sql request of scores
  con <- dbConnect(m, file.path(path, dbName))
    
  if(missing(tables))
    tables <- dbListTables(con)
  
  mirs <- as.character()
  for(table in tables)
    {      
      query <- paste("SELECT DISTINCT miRNA FROM ", table, " WHERE mRNA = '", target, "' ", sep="")
      x <- dbGetQuery(con, query)$miRNA                

      mirs <- c(mirs, x)
    }
  
  invisible(dbDisconnect(con))          #close connection
  
  mirs <- mirs[!duplicated(mirs)]
  ##targets[!is.na(targets)]
  mirs
}

##' Find unique microRNAs old
##'
##' Details will follow
##' @title Find unique microRNAs old
##' @param path to database
##' @param dbName database name
##' @param target specific target
##' @param tables tables in the database
##' @param full return whole matrix
##' @return unique microRNAs
##' @author Maarten van Iterson
overlapMircoRNAs <- function(path, dbName, tables=NULL, target, numOverlapping=2, full=TRUE)
  {    
    m <- dbDriver("SQLite")             # simple sql request of scores
    con <- dbConnect(m, file.path(path, dbName))

    if(is.null(tables))
      tables <- dbListTables(con)
    
    uMirs <- uniqueMirs(path, dbName, target)
    
    overlappingMirs <- matrix(FALSE, nrow=length(uMirs), ncol=length(tables))
    
    for(i in 1:length(tables))
      {
        mirs <- uniqueMirs(path, dbName, target, tables[i])
        overlappingMirs[,i] <- uMirs %in% mirs 
      }
   
    invisible(dbDisconnect(con))        #close connection
    
    colnames(overlappingMirs) <- tables
    rownames(overlappingMirs) <- uMirs    

    if(!full)
      overlappingMirs <- overlappingMirs[apply(overlappingMirs, 1, sum) >= numOverlapping, , drop=FALSE] #drop=FALSE in case one row left
    
    if(!any(apply(overlappingMirs, 1, sum) >= numOverlapping))
      {
      cat(paste(target, " has no overlapping microRNAs between the tables: ", paste(tables, collapse=", ", sep=""), "! ...\n", sep=""))
      return(NULL)
    }
    cat(paste(target, " has ", nrow(overlappingMirs), " overlapping microRNAs between the tables: ", paste(tables, collapse=", ", sep=""), "! ...\n", sep=""))
   
    overlappingMirs    
  }



