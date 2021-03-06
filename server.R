library(leaflet)
library(rgdal)
library(RColorBrewer)
library(scales)
library(lattice)
library(dplyr)

# Leaflet bindings are a bit slow; for now we'll just sample to compensate
# set.seed(100)
zipdata <- allzips[sample.int(nrow(allzips), 10000),]
# # By ordering by centile, we ensure that the (comparatively rare) SuperZIPs
# # will be drawn last and thus be easier to see
# zipdata <- zipdata[order(zipdata$centile),]

function(input, output, session) {

  ## Interactive Map ###########################################
colRow <- readOGR(".", "GLOBIOM_Grid_Prov_Rev")
  # Create the map
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles(
        urlTemplate = "//{s}.tiles.mapbox.com/v3/jcheng.map-5ebohr46/{z}/{x}/{y}.png",
        attribution = 'Maps by <a href="http://www.mapbox.com/">Mapbox</a>'
      ) %>%
      setView(lng = 118.0832, lat = -2.629957, zoom = 5)
  })

  # A reactive expression that returns the set of zips that are
  # in bounds right now
  zipsInBounds <- reactive({
    if (is.null(input$map_bounds))
      return(zipdata[FALSE,])
    bounds <- input$map_bounds
    latRng <- range(bounds$north, bounds$south)
    lngRng <- range(bounds$east, bounds$west)

    subset(zipdata,
      latitude >= latRng[1] & latitude <= latRng[2] &
        longitude >= lngRng[1] & longitude <= lngRng[2])
  })

  # Precalculate the breaks we'll need for the two histograms
  centileBreaks <- hist(plot = FALSE, allzips$centile, breaks = 20)$breaks

  output$histCentile <- renderPlot({
    # If no zipcodes are in view, don't plot
    if (nrow(zipsInBounds()) == 0)
      return(NULL)

    hist(zipsInBounds()$centile,
      breaks = centileBreaks,
      main = "SuperZIP score (visible zips)",
      xlab = "Percentile",
      xlim = range(allzips$centile),
      col = '#00DD00',
      border = 'white')
  })

  output$scatterCollegeIncome <- renderPlot({
    # If no zipcodes are in view, don't plot
    if (nrow(zipsInBounds()) == 0)
      return(NULL)

    print(xyplot(income ~ college, data = zipsInBounds(), xlim = range(allzips$college), ylim = range(allzips$income)))
  })

  # This observer is responsible for maintaining the circles and legend,
  # according to the variables the user has chosen to map to color and size.
  observe({
    typeBy <- input$type
    scenBy <- input$scen
    yearBy <- input$year
    colorBy <- input$color
    # sizeBy <- input$size
    # dummy data AD====
    # joinTable <- read.csv("master_data_wide.csv", stringsAsFactors= FALSE)
    joinTable <- colRowRds %>% filter(Type == paste0(typeBy) & Year == yearBy & Scen == paste0(scenBy))
    joinTable <- joinTable %>% rename_at(1, ~"GRID")
    colRow@data <- colRow@data %>% left_join(joinTable, by = "GRID")
    if (colorBy == "superzip") {
      # Color and palette are treated specially in the "superzip" case, because
      # the values are categorical instead of continuous.
      colorData <- ifelse(zipdata$centile >= (100 - input$threshold), "yes", "no")
      pal <- colorFactor("viridis", colorData)
    } else {
      colorData <- zipdata[[colorBy]]
      pal <- colorBin("viridis", colorData, 7, pretty = FALSE)
    }

    # if (sizeBy == "superzip") {
    #   # Radius is treated specially in the "superzip" case.
    #   radius <- ifelse(zipdata$centile >= (100 - input$threshold), 30000, 3000)
    # } else {
    #   radius <- zipdata[[sizeBy]] / max(zipdata[[sizeBy]]) * 30000
    # }

    # leafletProxy("map", data = zipdata) %>%
    #   clearShapes() %>%
    #   addCircles(~longitude, ~latitude, radius=radius, layerId=~zipcode,
    #     stroke=FALSE, fillOpacity=0.4, fillColor=pal(colorData)) %>%
    #   addLegend("bottomleft", pal=pal, values=colorData, title=colorBy,
    #     layerId="colorLegend")
    # AD misc====
    colorDat <- colRow@data %>% dplyr::select(colorBy) %>% pull()
    pale <- colorNumeric("viridis", colorDat)
    # AD misc \ends----

    leafletProxy("map", data = colRow) %>%  clearShapes() %>% addPolygons(weight = 1, smoothFactor = 0.5,
                                                                          opacity = 1.0, fillOpacity = 0.5,
                                                                          color = eval(parse(text= paste0("~pale(", colorBy,")"))),
                                                                          highlightOptions = highlightOptions(color = "white", weight = 2,
                                                                                                              bringToFront = TRUE)) %>% addLegend("bottomleft", pal=pale, values=colorDat, title="Tes1", layerId = "colorLegend")
    #     layerId="colorLegend")
  })

  # Show a popup at the given location
  showZipcodePopup <- function(zipcode, lat, lng) {
    selectedZip <- allzips[allzips$zipcode == zipcode,]
    content <- as.character(tagList(
      tags$h4("Score:", as.integer(selectedZip$centile)),
      tags$strong(HTML(sprintf("%s, %s %s",
        selectedZip$city.x, selectedZip$state.x, selectedZip$zipcode
      ))), tags$br(),
      sprintf("Median household income: %s", dollar(selectedZip$income * 1000)), tags$br(),
      sprintf("Percent of adults with BA: %s%%", as.integer(selectedZip$college)), tags$br(),
      sprintf("Adult population: %s", selectedZip$adultpop)
    ))
    leafletProxy("map") %>% addPopups(lng, lat, content, layerId = zipcode)
  }

  # When map is clicked, show a popup with city info
  observe({
    leafletProxy("map") %>% clearPopups()
    event <- input$map_shape_click
    if (is.null(event))
      return()

    isolate({
      showZipcodePopup(event$id, event$lat, event$lng)
    })
  })


  ## Data Explorer ###########################################

  observe({
    cities <- if (is.null(input$states)) character(0) else {
      filter(cleantable, State %in% input$states) %>%
        `$`('City') %>%
        unique() %>%
        sort()
    }
    stillSelected <- isolate(input$cities[input$cities %in% cities])
    updateSelectInput(session, "cities", choices = cities,
      selected = stillSelected)
  })

  observe({
    zipcodes <- if (is.null(input$states)) character(0) else {
      cleantable %>%
        filter(State %in% input$states,
          is.null(input$cities) | City %in% input$cities) %>%
        `$`('Zipcode') %>%
        unique() %>%
        sort()
    }
    stillSelected <- isolate(input$zipcodes[input$zipcodes %in% zipcodes])
    updateSelectInput(session, "zipcodes", choices = zipcodes,
      selected = stillSelected)
  })

  observe({
    if (is.null(input$goto))
      return()
    isolate({
      map <- leafletProxy("map")
      map %>% clearPopups()
      dist <- 0.5
      zip <- input$goto$zip
      lat <- input$goto$lat
      lng <- input$goto$lng
      showZipcodePopup(zip, lat, lng)
      map %>% fitBounds(lng - dist, lat - dist, lng + dist, lat + dist)
    })
  })

  output$ziptable <- DT::renderDataTable({
    df <- cleantable %>%
      filter(
        Score >= input$minScore,
        Score <= input$maxScore,
        is.null(input$states) | State %in% input$states,
        is.null(input$cities) | City %in% input$cities,
        is.null(input$zipcodes) | Zipcode %in% input$zipcodes
      ) %>%
      mutate(Action = paste('<a class="go-map" href="" data-lat="', Lat, '" data-long="', Long, '" data-zip="', Zipcode, '"><i class="fa fa-crosshairs"></i></a>', sep=""))
    action <- DT::dataTableAjax(session, df)

    DT::datatable(df, options = list(ajax = list(url = action)), escape = FALSE)
  })
}
