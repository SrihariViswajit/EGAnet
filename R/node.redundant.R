#' Detects Redundant Nodes in a Network
#' @description Identifies redundant nodes in the network based on several
#' measures. Computes the weighted topological overlap between
#' each node and every other node in the network. The weighted topological
#' overlap is implemented using the method from Nowick et al. (2009; see references)
#' and the function \link[wTO]{wTO} from the wTO package.
#'
#' @param data Matrix or data frame.
#' Input can either be data or a correlation matrix
#' 
#' @param n Numeric.
#' If input in \code{data} is a correlation matrix and
#' \code{method = "wTO"}, then sample size is required.
#' Defaults to NULL
#'
#' @param sig Numeric.
#' \emph{p}-value for significance of overlap (defaults to \code{.05}).
#' If more than 200 connections, then \code{\link[fdrtool]{fdrtool}}
#' is used to correct for false positives. In these instances, \code{sig}
#' sets the \emph{q}-value for significance of overlap (defaults to \code{.10})
#'
#' @param method Character.
#' Computes weighted topological overlap (\code{"wTO"} using \code{\link[qgraph]{EBICglasso}}),
#' partial correlations (\code{"pcor"}), or thresholding
#' based on a certain level of partial correlations (\code{"thresh"}).
#' \code{method = "thresh"} will use the argument \code{"sig"} to input
#' the desired threshold (defaults to \code{sig = .20}).
#'
#' @param type Character.
#' Computes significance using the standard \emph{p}-value (\code{"alpha"}),
#' bonferroni corrected \emph{p}-value (\code{"bonferroni"}),
#' false-discovery rate corrected \emph{p}-value (\code{"FDR"}),
#' or adaptive alpha \emph{p}-value (\code{\link[NetworkToolbox]{adapt.a}}).
#' Defaults to \code{"adapt"}
#'
#' @return Returns a list:
#'
#' \item{redundant}{Vectors nested within the list corresponding
#' to redundant nodes with the name of object in the list}
#'
#' \item{data}{Returns original data}
#'
#' \item{weights}{Returns weights determine by weighted topological overlap
#' or partial correlations}
#'
#' \item{network}{The network compute by \code{\link[qgraph]{EBICglasso}}}
#'
#' @examples
#' # obtain SAPA items
#' items <- psychTools::spi[,c(11:20)]
#' 
#' # weighted topological overlap
#' redund <- node.redundant(items, method = "wTO", type = "adapt")
#'
#' # partial correlation
#' redund <- node.redundant(items, method = "pcor", type = "adapt")
#' 
#' # threshold
#' redund <- node.redundant(items, method = "thresh", sig = .20)
#'
#' @references
#' # simulation using node.redundant
#' Christensen, A. P. (2020).
#' Towards a network psychometrics approach to assessment: Simulations for redundancy, dimensionality, and loadings
#' (Unpublished doctoral dissertation). University of North Carolina at Greensboro, Greensboro, NC, USA.
#' https://doi.org/10.31234/osf.io/84kgd
#' 
#' # wTO
#' Nowick, K., Gernat, T., Almaas, E., & Stubbs, L. (2009).
#' Differences in human and chimpanzee gene expression patterns define an evolving network of transcription factors in brain.
#' \emph{Proceedings of the National Academy of Sciences}, \emph{106}, 22358-22363.
#' https://doi.org/10.1073/pnas.0911376106
#'
#' @author Alexander Christensen <alexpaulchristensen@gmail.com>
#'
#' @importFrom stats pgamma pnorm
#'
#' @export
#
# Redundant Nodes Function
# Updated 15.06.2020
node.redundant <- function (data, n = NULL, sig, method = c("wTO", "pcor", "thresh"),
                            type = c("alpha", "bonferroni", "FDR", "adapt"))
{
  #### missing arguments handling ####
  
  if(missing(type))
  {type <- "adapt"
  }else{type <- match.arg(type)}
  
  #### missing arguments handling ####
  
  # change arguments to lower
  type <- tolower(type)
  method <- tolower(method)
  
  # check for correlation matrix
  if(ncol(data) == nrow(data))
  {
    A <- data
    
    # check for number of cases ("wTO" only)
    if(method == "wto")
    {
      if(is.null(n))
      {stop('Argument \'n\' is NULL. Number of cases must be specified when a correlation matrix is input into the \'data\' argument and method = "wTO"')}
    }
  }else{
    # correlate data
    A <- qgraph::cor_auto(data)
    # number of cases
    n <- nrow(data)
  }

  #compute redundant method
  if(method == "wto")
  {
    # compute network
    net <- EBICglasso.qgraph(A, n = n)
    tom <- wTO::wTO(net,sign="sign")
  }else if(method == "pcor" || method == "thresh")
  {tom <- -cov2cor(solve(A))}

  #number of nodes
  nodes <- ncol(tom)

  diag(tom) <- 0

  tom <- abs(tom)

  #lower triangle of TOM
  lower <- tom[lower.tri(tom)]

  #grab names for lower triangle
  name1 <- colnames(tom)
  name2 <- colnames(tom)

  #initialize name matrix
  name.mat <- tom

  #produce name matrix
  for(i in 1:nodes)
    for(j in 1:nodes)
    {name.mat[i,j] <- paste(name1[j],name2[i],sep="--")}

  #grab lower triangle names
  names(lower) <- name.mat[lower.tri(name.mat)]

  #obtain only positive values
  pos.vals <- na.omit(ifelse(lower==0,NA,lower))
  attr(pos.vals, "na.action") <- NULL

  if(type != "thresh")
  {
    #determine distribution
    ##distributions
    distr <- c("norm","gamma")
    aic <- vector("numeric", length = length(distr))
    names(aic) <- c("normal","gamma")

    for(i in 1:length(distr))
    {aic[i] <- fitdistrplus::fitdist(pos.vals,distr[i],method="mle")$aic}

    #obtain distribution parameters
    g.dist <- suppressWarnings(MASS::fitdistr(pos.vals, names(aic)[which.min(aic)]))

    #compute significance values
    pval <- switch(names(aic)[which.min(aic)],

                   normal = 1 - unlist(lapply(pos.vals, #positive wTo
                                              pnorm, #probability in normal distribution
                                              mean = g.dist$estimate["mean"], #mean of normal
                                              sd = g.dist$estimate["sd"]) #sd of normal
                   ),

                   gamma = 1 - unlist(lapply(pos.vals, #positive wTo
                                             pgamma, #probability in gamma distribution
                                             shape = g.dist$estimate["shape"], #shape of gamma
                                             rate = g.dist$estimate["rate"]) #rate of gamma
                   ),
    )
    
    #switch for missing arguments
    if(missing(sig))
    {
      sig <- switch(type,
                    fdr = .10,
                    bonferroni = .05,
                    adapt = .05,
                    alpha = .05
      )
    }else{sig <- sig}
    
    #switch to compute pvals
    if(type == "fdr")
    {
      pval <- suppressWarnings(fdrtool::fdrtool(pval, statistic = "pvalue", plot = FALSE, verbose = FALSE)$qval)
    }else{
      sig <- switch(type,
                    bonferroni = sig / length(pos.vals),
                    adapt = NetworkToolbox::adapt.a("cor", alpha = sig, n = length(pos.vals), efxize = "medium")$adapt.a,
                    alpha = sig
      )
    }

    #identify q-values less than sigificance
    res <- pos.vals[which(pval<=sig)]

  }else{
    sig <- ifelse(missing(sig),.20,sig)

    res <- pos.vals[which(abs(lower) > sig)]
  }

  #if no redundant, then print no redundant nodes
  if(length(res)==0)
  {
    message(paste("No redundant nodes identified. Increase 'sig' arugment to detect more nodes."))
    res.list <- NA
  }else{

    #create result matrix
    split.res <- unlist(strsplit(names(res), split = "--"))
    res.mat <- t(simplify2array(sapply(names(res), strsplit, split = "--")))

    #initialize result list
    res.list <- list()

    #initialize count
    count <- 0

    while(nrow(res.mat)!=0)
    {
      #increase count
      count <- count + 1

      #get variable counts
      var.counts <- sort(table(split.res), decreasing = TRUE)

      if(!all(var.counts==1))
      {
        #identify targets
        target <- which(res.mat == names(var.counts[1]), arr.ind = TRUE)[,"row"]

        #insert values into list
        res.list[[names(var.counts[1])]] <- setdiff(unlist(strsplit(names(target),split="--")),names(var.counts[1]))

        #remove rows from result matrix
        res.mat <- res.mat[-target,]

        #remove variables from split result
        split.res <- as.vector(res.mat)

        #force matrix
        if(is.vector(res.mat))
        {res.mat <- t(as.matrix(res.mat))}

      }else
      {
        for(i in 1:nrow(res.mat))
        {res.list[[res.mat[i,1]]] <- unname(res.mat[i,2])}

        res.mat <- res.mat[-c(1:nrow(res.mat)),]
      }
    }
  }

  full.res <- list()
  full.res$redundant <- res.list
  full.res$data <- data
  full.res$weights <- tom
  if(exists("net"))
  {full.res$network <- net}

  class(full.res) <- "node.redundant"

  return(full.res)
}
#----
