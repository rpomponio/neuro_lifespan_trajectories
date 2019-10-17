library(plotly)

df.lifespan.pred <- read.csv("input_datasets/data_lifespan_age_trajectories.csv", stringsAsFactors=F)
roi.columns <- colnames(df.lifespan.pred)[grepl("^R\\d+", colnames(df.lifespan.pred))]

# load roi dictionary
df.dict <- read.csv("input_datasets/ISTAGING_ROI_dictionary_20190109.csv", stringsAsFactors=F)
df.dict <- subset(df.dict, ROI_COL%in%roi.columns)
df.dict$ROI_LABEL <- paste0("[", df.dict$ROI_COL, "] ", df.dict$ROI_NAME)

fluidPage(
  headerPanel("LIFESPAN Age Trends of Neuroimaging-derived Brain Structures"),
  fluidRow(
    column(4,
           wellPanel(h4("Selected ROI"),
                     selectInput("ROI.COL", "", df.dict$ROI_LABEL)),
           wellPanel(h4("View Control"),
                     checkboxInput("SEPARATE.SEXES", "View separate age trends for males/females", FALSE),
                     p("Note: This will disable SEX and ICV correction. Harmonization with new data may not be accurate.")),
           wellPanel(h4("Upload New Site Data"),
                     p("Data must contain AGE, SEX, ICV, and ROI columns (e.g. R4)"),
                     helpText(a("Click Here for Help",
                                href="https://github.com/rpomponio/neuro_lifespan_trajectories",
                                target="_blank")),
                     fileInput("NEWDATA", "Choose CSV File",
                               multiple=FALSE,
                               accept=c("text/csv", "text/comma-separated-values,text/plain", ".csv")),
                     checkboxInput("CORRECT.NEWDATA", "Correct for SEX, ICV effects (recommended)", TRUE),
                     checkboxInput("HARMONIZE.NEWDATA", "Harmonize to LIFESPAN Age Trend", FALSE),
                     checkboxInput("HARMONIZE.NEWDATA.SCALE", "Include Scale Effect in Harmonization (recommended)", TRUE))
           ),
    column(8,
           tabsetPanel(type="tabs",
                       tabPanel("Age Trend",
                                h4("Age Trend Estimated with LIFESPAN Dataset"),
                                p("Dashed lines represent approximate data variability around trendline."),
                                plotlyOutput("scatterplot.age", height="600px")),
                       tabPanel("Lifespan Table",
                                dataTableOutput("lifespan.table"),
                                p("Data summarized into a table by decades of the human lifespan.")))
    )
  )
)
