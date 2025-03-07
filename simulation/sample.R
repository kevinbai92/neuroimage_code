#################################################
rm(list=ls())
gc()

######## Loading Packages #######################
library("mvtnorm")
library("lattice")
library("RColorBrewer")
library("factoextra")
library("Rcpp")
library("sparsevar")
library("RcppArmadillo")
library("MTS")
library("ggplot2")

######## Call Functions #########################
source("functions_BFL.R")
#cpp code for block fused lasso and block lasso
sourceCpp("functions_BFL.cpp")

#################################################
### universal parameter settings
T <- 1000     ### the number of observations
p <- 20       ### dimension of time series
brk <- c(floor(T/3), floor(2*T/3), T+1)   ### true interval end points
m0 <- length(brk) - 1   ### true number of break points
q.t <- 1      ### true time lag

### generate time series
m <- m0 + 1
phi.full <- matrix(0, p, p*q.t*m)
aa <- 0.8
set.seed(123)
for(mm in 1:m){
    phi.full[,((mm-1)*q.t*p+1):((mm)*q.t*p)] <- 0
    for (j in 1:(p-1)){
        bool_1 <- sample(0:2, 1, prob = c(0.1,0.8,0.1))
        x_shift = sample(0:4, 1)
        if (bool_1 > 0 &&  (j + x_shift[1:bool_1] <= p) ){
            phi.full[j,((mm-1)*q.t*p+j +  x_shift[1:bool_1])] <- -aa
        }
    }
    if(mm %% 2 == 0){
        phi.full[,((mm-1)*q.t*p+1):((mm)*q.t*p)]  <- -phi.full[,((mm-1)*q.t*p+1):((mm)*q.t*p)]
    }
}  

#display the true AR coefficients matrice
print(plot.ar.matrix((phi.full), m))

#################################################
max_iter <- 1
cases_ret <- list()
estimated_times <- NULL
estimated_cps <- vector('list', max_iter)
estimated_mats <- vector('list', max_iter)
for(epoch in 1:max_iter){
    ### generate time series
    set.seed(123456*epoch)
    e.sigma <- as.matrix(0.1*diag(p));
    try <- var.sim.break(T, arlags = q.t, malags = NULL, phi = phi.full, sigma = e.sigma, brk = brk)
    data <- try$series
    data <- as.matrix(data)
    
    ### run the bss method, get the estimated change points and a_n
    begin_time <- proc.time()
    ret <- tbfl(method = 'VAR', data_y = data, max.iteration = 100, tol = 5e-2)
    end_time <- proc.time()
    
    ### get estimated transition matrices
    final.estimated.intervals <- c(1, ret$cp.final, T)
    an <- floor(sqrt(T))
    estimated_blockmats <- NULL
    for(j in 2:length(final.estimated.intervals)){
        s <- final.estimated.intervals[j-1] + floor(an/2)
        e <- final.estimated.intervals[j] - floor(an/2)
        
        interval_data <- data[s:e, ]
        var.fit <- fitVAR(interval_data, penalty = 'ENET', alpha = 1, intercept = FALSE)
        temp_mat <- var.fit$A[[1]]
        estimated_blockmats <- cbind(estimated_blockmats, temp_mat)
    }
    
    ### record results into lists 
    estimated_times <- c(estimated_times, (end_time - begin_time)[3])
    estimated_cps[[epoch]] <- ret$cp.final
    estimated_mats[[epoch]] <- estimated_blockmats
    
    print(epoch)
}
### record results for cases lists
cases_ret$times <- estimated_times
cases_ret$CPs <- estimated_cps
cases_ret$Matrices <- estimated_mats

#####################################################################################
running_times <- mean(cases_ret$times)
print(paste("average running times:", running_times))

# evaluate the mean, sd, and selection rate of estimated CPs
true_brk <- brk[1:2]
cps <- cases_ret$CPs
cp1 = cp2 <- NULL
for(i in 1:max_iter){
    iter_cps <- cps[[i]]
    for(j in 1:length(iter_cps)){
        current_cp <- iter_cps[j]
        if(current_cp <= 400 && current_cp >= 300){
            cp1 <- c(cp1, current_cp)
        }else if(current_cp <= 700 && current_cp >= 600){
            cp2 <- c(cp2, current_cp)
        }else{
            next
        }
    }
}
mean(cp1/T); sd(cp1/T); length(cp1)/max_iter
mean(cp2/T); sd(cp2/T); length(cp2)/max_iter

# 2. evaluate the transition matrices
evaluate <- function(true_mat, est_mat, method){
    method.full <- c('SEN', 'FNR', 'ACC')
    nr <- nrow(true_mat)
    nc <- ncol(true_mat)
    
    ### calculate confusion matrix
    tp = fn = tn = fp <- 0
    for(i in 1:nr){
        for(j in 1:nc){
            if(true_mat[i,j] != 0){
                if(est_mat[i,j] != 0){
                    tp <- tp + 1
                }else if(est_mat[i,j] == 0){
                    fn <- fn + 1
                }
            }else if(true_mat[i,j] == 0){
                if(est_mat[i,j] != 0){
                    fp <- fp + 1
                }else if(est_mat[i,j] == 0){
                    tn <- tn + 1
                }
            }
        }
    }
    if(method == 'SEN'){
        return(tp / (tp + fn))
    }else if(method == 'FNR'){
        return(fp / (fp + tn))
    }else if(method == 'ACC'){
        return((tp + tn) / (tp + tn + fp + fn))
    }
}

mats <- cases_ret$Matrices
sen = spc = acc <- NULL
re <- NULL
for(i in 1:max_iter){
    est_mats <- mats[[i]]
    if(ncol(est_mats) / nrow(est_mats) == 3){
        sen <- c(sen, evaluate(phi.full, est_mats, method = 'SEN'))
        spc <- c(spc, 1-evaluate(phi.full, est_mats, method = 'FNR'))
        acc <- c(acc, evaluate(phi.full, est_mats, method = 'ACC'))
        re <- c(re, norm(phi.full - est_mats, "F")/norm(phi.full, "F"))
    }
}
mean(sen)
mean(spc)
mean(re)
