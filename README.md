# miRNAmRNA #
A framework for microRNA mRNA expression data integrated analysis

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Example](#example)

## Features ##
- describe features

## Installation ##
If you want to install the latest development version use the devtools package to install the miRNAmRNA package. 
Dependency of the package are: AnnotationDbi, RSQLite, org.Mm.eg.db, org.Hs.eg.db, limma, globaltest all of which can be install using BioConductor's biocLite.
```s
library(devtools)
install_git('https://git.lumc.nl/mvaniterson/mirnamrna.git')
```

## Example ##
Analysis of C2C12 cell miRNA and mRNA expression data using the miRNAmRNA-package. This analysis briefly describes the analysis performed in 
[vanIterson2013](http://nar.oxfordjournals.org/content/41/15/e146.long)

Download target predictions manually from PITA, TargetScan and microCosm. Optionally construct parser for other prediction tools see ?addTable.

```s
library(miRNAmRNA)
dataDir <- "pathToData"
resultsDir <- "pathToResults"
dbName <- "mir.Mm.db"
filePITA <- file.path(dataDir, "targets_data", "PITA_targets_mm9_0_0_TOP.tab")
fileMicrocosm <- file.path(dataDir, "targets_data", "v5.gff.mus_musculus")  
fileTargetScan <- file.path(dataDir, "targets_data", "Conserved_Site_Context_Scores61.txt")
``` 

Construct the database and inspect its contents.

```s
addTable(filePITA, tableName="pita", path=reultsDir, dbName=dbName, Org="Mm") 
addTable(fileMicrocosm, tableName="microcosm", path=resultsDir, dbName=dbName, Org="Mm") 
addTable(fileTargetScan, tableName="targetscan", path=resultsDir, dbName=dbName, Org="Mm") 
dbInfo(resultsDir, dbName)
dbHeadTable(resultsDir, dbName, "pita")
dbHeadTable(resultsDir, dbName, "targetscan")
dbHeadTable(resultsDir, dbName, "microcosm", n=10)
``` 

Download microRNA and mRNA expression data and perform some preprocessing steps such as identifier mapping.

```s
##extract and process data
library(GEOquery)
miRNA <- getGEO(filename=file.path(dataDir, "expression_data", "GSE9449_series_matrix.txt.gz")) #also available from ArrayExpress E-GEOD-9449
miFeature <- pData(featureData(miRNA))
miExprs <- exprs(miRNA)
colnames(miExprs) <- c("Prol", "Conf", "+1d", "+2d", "+4d")
 
strwhite <- function(x)
  {
    x <- sub("^[[:blank:]]*", "", x, perl=TRUE) ##leading
    x <- sub("[[:blank:]]*$", "", x, perl=TRUE) ##trailing
    x
  }

extractID <- function(x)
  {
    y <- unlist(strsplit(x, ","))
    idx <- sapply(y, grepl, pattern="mmu")
    if(any(idx))
      return(strwhite(y[idx]))
    NA
  }

mirID <- sapply(as.character(miFeature$SPOT_ID), extractID, USE.NAMES=FALSE)
rownames(miExprs) <- mirID
miExprs <- miExprs[,-4] 
miExprs <- miExprs[!is.na(rownames(miExprs)), ]
miExprs <- miExprs[!duplicated(rownames(miExprs)),]
##some manual edits
rownames(miExprs)[rownames(miExprs) == "mmu-miR-291a5p291b5p"] <- "mmu-miR-291a5p"
rownames(miExprs)[rownames(miExprs) == "mmu-miR-133a133b"] <- "mmu-miR-133a"
save(miExprs, file=file.path(resultsDir, "miExprs.RData"))
``` 

```s
mRNA <- getGEO(filename=file.path(dataDir, "expression_data", "GSE19968_series_matrix.txt.gz")) 
mFeature <- pData(featureData(mRNA))
mExprs <- exprs(mRNA)
mExprs <- cbind(rowMeans(mExprs[,1:3]), rowMeans(mExprs[,4:6]), rowMeans(mExprs[,7:9]), rowMeans(mExprs[,10:12]))
colnames(mExprs) <- c("Myoblast", "T0", "T24", "Myotube")
mExprs <- mExprs[!duplicated(mFeature$GENE),,drop=FALSE] #extra calculation: remove all the mRNAs that map to the same Gene just using one transcript
rownames(mExprs) <- mFeature$GENE[!duplicated(mFeature$GENE)]
save(mExprs, file=file.path(resultsDir, "mExprs.RData"))
``` 

Run the integrated analysis.

```s
library(miRNAmRNA)
dbName <- "mir.Mm.db"
resultsDir <- "pathToResults"
load(file.path(resultsDir, "mExprs.RData"))
load(file.path(resultsDir, "miExprs.RData"))
results <- rungt(mirs=rownames(miExprs), X=mExprs, Y=miExprs, path=resultsDir, dbName=dbName, tables=c("microcosm", "pita", "targetscan"), numOverlapping=3)
save(results, file=file.path(resultsDir, "C2C12pairs.RData"))
``` 

```s
library(lattice)
library(directlabels)
resultsDir <- "pathToResults"
load(file.path(resultsDir, "miExprs.RData"))
load(file=file.path(resultsDir, "C2C12pairs.RData"))
topMirs <- head(results$mirs, n=20)
X <- miExprs[rownames(miExprs) %in% rownames(topMirs), ]
data <- data.frame(miExpr = as.vector(X),
                   Time =  rep(factor(colnames(X), levels = colnames(X), ordered=TRUE), each=nrow(X)),
                   miRNA = gsub("mmu-", "", rep(rownames(X), ncol(X))))
print(direct.label(xyplot(miExpr~Time, groups=miRNA, data, type=c("b", "g"), lwd=2, ylab=expression('Normalized '*log[2]*' ratio'),
             scales = list(x = list(labels = colnames(X))))))
``` 

```s
library(xtable)
resultsDir <- "pathToResults"
load(file=file.path(resultsDir, "C2C12pairs.RData"))
topMirs <- head(results$mirs, n=20)
topMiExprs <- miExprs[rownames(miExprs) %in% rownames(topMirs),c(1,4)]
mirExprs <- topMiExprs[,1] < topMiExprs[,2]
mirExprs[mirExprs==TRUE] <- "up"
mirExprs[mirExprs==FALSE] <- "down"
topMirs <- merge(topMirs, mirExprs, by="row.names")
colnames(topMirs) <-  c("miRNA", "P-value", "\\# targets", "Regulation")
xtable(topMirs[order(topMirs$'P-value'), ],
       display=c("d", "s", "f", "d", "s"), digits= c(0, 0, 5, 0, 0),
       caption="Overview of significant miRNA target sets with strict overlap between the three prediction tools TargetScan, MicroCosm and PITA.")
``` 

```s
mir22 <- results$targets[["mmu-miR-22"]]
mir22 <- cbind(Symbol = unlist(mget(rownames(results$targets[["mmu-miR-22"]]), org.Mm.egSYMBOL, ifnotfound=NA)), mir22)
mir22$Association[mir22$Association == 0] <- "neg."
mir22$Association[mir22$Association == 1] <- "pos."
mir133a <- results$targets[["mmu-miR-133a"]]
mir133a <- cbind(Symbol = unlist(mget(rownames(results$targets[["mmu-miR-133a"]]), org.Mm.egSYMBOL)), mir133a)
mir133a$Association[mir133a$Association == 0] <- "neg."
mir133a$Association[mir133a$Association == 1] <- "pos."
mir26a <- results$targets[["mmu-miR-26a"]]
mir26a <- cbind(Symbol= unlist(mget(rownames(results$targets[["mmu-miR-26a"]]), org.Mm.egSYMBOL)), mir26a)
mir26a$Association[mir26a$Association == 0] <- "neg."
mir26a$Association[mir26a$Association == 1] <- "pos."
```

```s
print(xtable(mir22[,-c(4,5)],
       display=c("d", "s", "f", "s"), digits=c(0,0,5,0),
       caption="Overview of microRNA mmu-miR-22 targets with strict overlap between the three databases TargetScan, Microcosm and PITA."),
       tabular.environment="longtable", floating=FALSE)
```        

```s
print(xtable(mir133a[,-c(4,5)],
       display=c("d", "s", "f", "s"), digits=c(0,0,5,0),
       caption="Overview of microRNA mmu-miR-133a targets with strict overlap between the three databases TargetScan, Microcosm and PITA."),
       tabular.environment="longtable", floating=FALSE)
```

```s
print(xtable(mir26a[,-c(4,5)],
       display=c("d", "s", "f", "s"), digits=c(0,0,5,0),
       caption="Overview of microRNA mmu-miR-26a targets with strict overlap between the three databases TargetScan, Microcosm and PITA."),
       tabular.environment="longtable", floating=FALSE)
```


