library(GenomicRanges)

gistic2GR = function(locs, padding=0) {
  require(GenomicRanges)
  pos.split = as.data.frame(strsplit(as.character(locs), ":"), stringsAsFactors=FALSE)
  chr = toupper(gsub("chr", "", as.character(pos.split[1,])))
  chr = factor(chr, levels = c(1:22, "X", "Y"))
  start.end = as.data.frame(strsplit(as.character(pos.split[2,]), "-"), stringsAsFactors=FALSE)
  start = as.numeric(start.end[1,])-padding
  end = as.numeric(start.end[2,])+padding
  
  gr = GRanges(seqnames=Rle(chr), ranges = IRanges(start = start, end = end, names=chr))
  return(gr)
}


intersect.gistic = function(gistic.file1, gistic.file2, id1=basename(gistic.file1), id2=basename(gistic.file2), padding=1e6, max.genes=25, max.size=10e6, keep.non.focal=FALSE) {
  
  ## Read in gistic files    
  gistic1 = read.table(gistic.file1, sep="\t", stringsAsFactors=FALSE, header=FALSE, quote="")[,-1]
  gistic2 = read.table(gistic.file2, sep="\t", stringsAsFactors=FALSE, header=FALSE, quote="")[,-1]

  ## Add numbers of genes to file
  gistic1.num.genes = apply(gistic1[-(1:7),]!= "", 2, sum)
  gistic2.num.genes = apply(gistic2[-(1:7),]!= "", 2, sum)
  gistic1 = rbind(gistic1[1:7,], gistic1.num.genes)
  gistic2 = rbind(gistic2[1:7,], gistic2.num.genes)
    
  ## Intersect target genes
  target.genes = setdiff(intersect(gistic1[5,], gistic2[5,]), "")
  
  if(length(target.genes) > 0) {
    m1 = match(target.genes, gistic1[5,])
    m2 = match(target.genes, gistic2[5,])
    gistic1.overlapping.targets = gistic1[,m1]
    gistic2.overlapping.targets = gistic2[,m2]
    gistic1.other = gistic1[,-m1]
    gistic2.other = gistic2[,-m2]
  } else {
    gistic1.other = gistic1
    gistic2.other = gistic2
  }
  ## Put out other peaks with known target gene or less than max number of target genes to examine for overlaps
  ## Also pull out peaks with large number of genes and no listed target gene. These will not be considered for overlaps
  temp = gistic2GR(as.character(gistic1.other[4,]))
  gistic1.size = width(temp)
  ind =  gistic1.other[5,] != "" | (gistic1.size < max.size & as.numeric(gistic1.other[8,]) < max.genes)
  if(sum(!ind) > 0) {  
    gistic1.not.focal = gistic1.other[,!ind]
  } else {
    gistic1.not.focal = NULL
  }
  if(sum(ind) > 0) {
    gistic1.other = gistic1.other[,ind]
    gistic1.other.gr = gistic2GR(as.character(gistic1.other[4,]), padding=padding)
  } else {
    gistic1.other = NULL
  }

  temp = gistic2GR(as.character(gistic2.other[4,]))
  gistic2.size = width(temp)
  ind =  gistic2.other[5,] != "" | (gistic2.size < max.size & as.numeric(gistic2.other[8,]) < max.genes)
  if(sum(!ind) > 0) {  
    gistic2.not.focal = gistic2.other[,!ind]
  } else {
    gistic2.not.focal = NULL
  }
  if(sum(ind) > 0) {
    gistic2.other = gistic2.other[,ind]  
    gistic2.other.gr = gistic2GR(as.character(gistic2.other[4,]), padding=padding)  
  } else {
    gistic2.other = NULL
  }
  
  ## Find overlapping peaks without known targets
  if(!is.null(gistic1.other) & !is.null(gistic2.other)) {
    fo = findOverlaps(gistic1.other.gr, gistic2.other.gr) 
    if(length(fo) > 0) { 
      temp = data.frame(id1, t(gistic1.other[,queryHits(fo)]), id2, t(gistic2.other[,subjectHits(fo)]), stringsAsFactors=FALSE)
      ind = temp[,6] == "" | temp[,15] == ""   ## If the peaks overlap but the known target genes are different, then remove from the overlap list. However if at least one is unknown, then keep
      fo = fo[ind]
    }
  } else {
    fo = NULL
  }  	  



  ## Combine overlaps/nonoverlaps into a single data.frame
  
  ## Known target genes
  if(length(target.genes) > 0) {
    gistic.final = data.frame(id1, t(gistic1.overlapping.targets), id2, t(gistic2.overlapping.targets))
  } else {
    gistic.final = c()
  }
  
  ## Overlapping peaks without a target gene
  if(!is.null(fo)) {
    if(length(fo) > 0) {
      temp = data.frame(id1, t(gistic1.other[,queryHits(fo)]), id2, t(gistic2.other[,subjectHits(fo)]), stringsAsFactors=FALSE)
      gistic.final = rbind(gistic.final, temp) 
    } 
  }
  
  ## Peaks specific to gistic1 but focal (<max.genes) or have a target gene 
  gistic1.no.overlap.ix = setdiff(1:length(gistic1.other.gr), queryHits(fo))
  if(length(gistic1.no.overlap.ix) > 0) {
    gistic1.no.overlap = gistic1.other[,gistic1.no.overlap.ix]
    na.matrix = matrix(NA, ncol=8, nrow=ncol(gistic1.no.overlap))
    gistic.final = rbind(gistic.final, data.frame(id1, t(gistic1.no.overlap), id2, na.matrix))  
  }
  
  ## Peaks specific to gistic2 but focal (<max.genes) or have a target gene
  gistic2.no.overlap.ix = setdiff(1:length(gistic2.other.gr), subjectHits(fo))
  if(length(gistic2.no.overlap.ix) > 0) {
    gistic2.no.overlap = gistic2.other[,gistic2.no.overlap.ix]
    na.matrix = matrix(NA, ncol=8, nrow=ncol(gistic2.no.overlap))
    gistic.final = rbind(gistic.final, data.frame(id1, na.matrix, id2, t(gistic2.no.overlap)))  
  }
  
  ## All other gistic1 non-focal peaks are added as well
  if(!is.null(gistic1.not.focal)) {
    if(nrow(gistic1.not.focal) > 0 & keep.non.focal == TRUE) {
      na.matrix = matrix(NA, ncol=8, nrow=ncol(gistic1.not.focal))
      gistic.final = rbind(gistic.final, data.frame(id1, t(gistic1.not.focal), id2, na.matrix))  
    }
  }  
  ## All other gistic2 non-focal peaks are added as well
  if(!is.null(gistic2.not.focal)) {
    if(nrow(gistic2.not.focal) > 0 & keep.non.focal == TRUE) {
      na.matrix = matrix(NA, ncol=8, nrow=ncol(gistic2.not.focal))
      gistic.final = rbind(gistic.final, data.frame(id1, na.matrix, id2, t(gistic2.not.focal)))  
    }
  }  
 
  numeric.cols = c(3,4,9,12,13,18)
  gistic.final[,numeric.cols] = apply(gistic.final[,numeric.cols], 2, as.numeric)
  colnames(gistic.final) = c("ID1", "cytoband1", "q_value1", "residual_q_value1", "wide_peak_boundries1", "cancer_gene1", "label1", "representative_gene1", "number_of_genes1", "ID2", "cytoband2", "q_value2", "residual_q_value2", "wide_peak_boundries2", "cancer_gene2", "label2", "respresentative_gene2", "number_of_genes2")
  return(gistic.final)
}


gistic.intersect.focal.peaks = function(gistic.files, max.genes=25, max.size=10e6, padding=1e6) {

  total.gr = c()
  
  require(GenomicRanges)
  for(i in gistic.files) {
    temp.gistic = read.table(i, sep="\t", stringsAsFactors=FALSE, header=FALSE, quote="")[,-1]

    temp = gistic2GR(as.character(temp.gistic[4,]))
    gistic.size = width(temp)

    temp.gistic.num.genes = apply(temp.gistic[-(1:7),]!= "", 2, sum)
    temp.gistic = rbind(temp.gistic[1:7,], temp.gistic.num.genes)
    ind = (as.numeric(temp.gistic[8,]) < max.genes & gistic.size < max.size) | temp.gistic[5,] != ""
    temp.gistic=temp.gistic[,ind]  
    
    temp.gistic.gr = gistic2GR(temp.gistic[4,], padding=padding)
    
    if(length(total.gr) > 0) {
      total.gr = c(total.gr, temp.gistic.gr)
    } else {
      total.gr = temp.gistic.gr
    }
  }
  
  return(total.gr)
}


plot.peak.expression = function(c, g, cnv.states = c(-2,-1,0,1,2), cnv.col = c("blue", "lightblue", "white", "indianred1", "red"), plot.kruskal=TRUE, plot.legend=TRUE, min.p=0.001, ...) {
  require(vioplot)
  
  boxplot(g ~ factor(c, levels=cnv.states), xaxt="n", border="grey25", lwd=0.5, boxwex=0.5, xaxt="n", col=cnv.col, ...)

  for(j in 1:length(cnv.states)) {
    ind = c == cnv.states[j] 
    if(sum(ind) > 0) {
      vioplot(g[ind], col=F, drawRect=F, add=TRUE, at=j)
    }  
  }

  if(plot.kruskal == TRUE) {
    k = kruskal.test(g ~ as.factor(c))
  
    if(k$p.value < min.p) {
      label = paste("p<", min.p, sep="")
    } else {
      label = paste("p=", round(k$p.value, abs(ceiling(log10(min.p)))), sep="")
    }
    
    text(2, max(g)-0.5, label)
  }  
  
  if(plot.legend == TRUE) {
    legend("bottomright", legend=as.character(cnv.states), col=cnv.col, pch=15)
  }

}

