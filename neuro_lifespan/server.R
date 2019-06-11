
library(ggplot2)
library(plotly)

theme_set(theme_bw(base_size=18))

# change upload size to 30 MB
options(shiny.maxRequestSize=30*1024^2)

# load main data
df.lifespan.pred <- read.csv("input_datasets/data_lifespan_age_trajectories.csv", stringsAsFactors=F)
roi.columns <- colnames(df.lifespan.pred)[grepl("^R\\d+", colnames(df.lifespan.pred))]

# load covariate coefficients
df.linear.coef <- read.csv("input_datasets/data_roi_covariate_correction_coefficients.csv", stringsAsFactors=F)

# load scale estimates
df.roi.rmse <- read.csv("input_datasets/data_roi_rmse_estimates.csv", stringsAsFactors=F)

# load roi dictionary
df.dict <- read.csv("input_datasets/ISTAGING_ROI_dictionary_20190109.csv", stringsAsFactors=F)
df.dict <- subset(df.dict, ROI_COL%in%roi.columns)
df.dict$ROI_LABEL <- paste0("[", df.dict$ROI_COL, "] ", df.dict$ROI_NAME)

# helper function to query lifespan predictions
query_age_predictions<- function(ages, roi_col="R4", sex=NA, df=df.lifespan.pred){
  results <- rep(NA, length(ages))
  for (i in 1:length(ages)){
    age <- ages[i]
    row_index <- which.min(abs(df$AGE - age))
    if (is.na(sex[i])){
      results[i] <- df[row_index, roi_col]
    } else {
      if (sex[i]=="M"){
        results[i] <- df[row_index, paste0(roi_col, "_MALE")]
      } else {
        results[i] <- df[row_index, paste0(roi_col, "_FEMALE")]
      }
    }
  }
  return(results)
}

function(input, output, session) {
  
  # SELECT ROI
  selectedROI <- reactive({
    df.dict[df.dict$ROI_LABEL==input$ROI.COL, ]$ROI_COL
  })
  
  # PREDICT FOR DECADES OF LIFESPAN DATA
  predictedDecades <- reactive({
    age.seq.decade <- seq(10, 90, 10)
    df.pred.decade <- data.frame(AGE=age.seq.decade)
    df.pred.decade$PRED <- query_age_predictions(df.pred.decade$AGE, roi_col=selectedROI())
    df.pred.decade$PRED_LAG <- c(NA, df.pred.decade$PRED[1:8])
    df.pred.decade$PRED_DELTA <- (df.pred.decade$PRED - df.pred.decade$PRED_LAG) / df.pred.decade$PRED_LAG
    
    df.pred.decade
  })
  
  # HANDLE NEW DATASET IF PROVIDED
  newData <- reactive({
    if (!is.null(input$NEWDATA)){
      new.data <- read.csv(input$NEWDATA$datapath, stringsAsFactors=F)
      # generate IDs
      if (!"ID"%in%colnames(new.data)){
        new.data$ID <- 1:nrow(new.data)
      }
      # correct for SEX, ICV effects, then rescenter to mean volume
      if (input$CORRECT.NEWDATA){
        if (!input$SEPARATE.SEXES){
          covar.coef <- df.linear.coef[, selectedROI()]
          new.mod <- model.matrix(~ SEX + ICV, data=new.data)
          original.volumes <- new.data[, selectedROI()]
          mean.original.volumes <- mean(new.data[, selectedROI()])
          predicted.volumes <- new.mod%*%covar.coef
          corrected.volumes <- original.volumes - predicted.volumes
          new.data[, selectedROI()] <- corrected.volumes + mean.original.volumes
        }
      }
      # harmonize new data to lifespan trajectory
      if (input$HARMONIZE.NEWDATA){
        if (!input$SEPARATE.SEXES){
          new.data$PRED_VOLUME <- query_age_predictions(new.data$AGE, roi_col=selectedROI())
        } else {
          new.data$PRED_VOLUME <- query_age_predictions(new.data$AGE, roi_col=selectedROI(), sex=new.data$SEX)
        }
        new.data$RESID_VOLUME <- new.data[, selectedROI()] - c(new.data$PRED_VOLUME)
        location.effect <- mean(new.data$RESID_VOLUME)
        if (input$HARMONIZE.NEWDATA.SCALE){
          scale.effect <- sd(new.data$RESID_VOLUME) / df.roi.rmse[df.roi.rmse$ROI_COL==selectedROI(), "RMSE"]
          rescaled.residuals <- (new.data$RESID_VOLUME - location.effect) / scale.effect
          new.data[, selectedROI()] <- new.data$PRED_VOLUME + rescaled.residuals
        } else {
          new.data[, selectedROI()] <- new.data[, selectedROI()] - location.effect
        }
      }
      new.data
    } else { NULL }
  })
  
  # SCATTERPLOT OF ROI VOLUMES BY AGE
  output$scatterplot.age <- renderPlotly({
    # adjust y-axis lims based on UI
    default.y.axis.min <- min(df.lifespan.pred[, paste0(selectedROI(), "_LWR")])
    default.y.axis.max <- max(df.lifespan.pred[, paste0(selectedROI(), "_UPR")])
    default.y.axis.lims <- c(default.y.axis.min, default.y.axis.max)
    custom.y.axis.constant <- 1.0 * (default.y.axis.lims[2] - default.y.axis.lims[1]) / 2
    custom.y.axis.lims <- c(default.y.axis.lims[1] - custom.y.axis.constant, default.y.axis.lims[2] + custom.y.axis.constant)
    gg <- ggplot(df.lifespan.pred, aes(x=AGE)) +
      labs(x="Age", y="ROI Volume") +
      ylim(custom.y.axis.lims)
    if (!is.null(input$NEWDATA)){
      if (input$SEPARATE.SEXES){
        gg <- gg +
          geom_point(data=subset(newData(), SEX=="M"), aes_string(y=selectedROI(), label="ID"), color="blue", alpha=0.5, size=3) +
          geom_point(data=subset(newData(), SEX=="F"), aes_string(y=selectedROI(), label="ID"), color="green", alpha=0.5, size=3)
      } else {
        gg <- gg +
          geom_point(data=newData(), aes_string(y=selectedROI(), label="ID"), color="red", alpha=0.5, size=3)
      }
    }
    if (input$SEPARATE.SEXES){
      gg <- gg +
        geom_line(aes_string(y=paste0(selectedROI(), "_MALE"), color=shQuote("Male"))) +
        geom_line(aes_string(y=paste0(selectedROI(), "_FEMALE"), color=shQuote("Female"))) +
        scale_color_manual(name="Sex", values=c(Male="blue", Female="green"))
    } else {
      gg <- gg +
        geom_line(aes_string(y=selectedROI()), color="black") +
        geom_line(aes_string(y=paste0(selectedROI(), "_UPR")), color="black", linetype="dashed") +
        geom_line(aes_string(y=paste0(selectedROI(), "_LWR")), color="black", linetype="dashed") +
        geom_point(data=predictedDecades(), aes(x=AGE, y=PRED), color="black")
    }
    
    ggplotly(gg) %>% layout(legend=list(x=0.05, y=0.95))
  })
  
  # DISPLAY TABLE OF PREDICTED CHANGES BY DECADE
  output$lifespan.table <- renderDataTable({
    tmp.df.pred.decade <- predictedDecades()
    tmp.df.pred.decade$PRED <- round(tmp.df.pred.decade$PRED, 3)
    tmp.df.pred.decade$PRED_LAG <- NULL
    tmp.df.pred.decade$PRED_DELTA <- round(100*tmp.df.pred.decade$PRED_DELTA, 3)
    names(tmp.df.pred.decade) <- c("Age", "PredictedVolume", "PercentChange")
    
    tmp.df.pred.decade
  })
  
  
  
  
  
  
  
  
  
}