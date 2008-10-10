FacetWrap <- proto(Facet, {
  new <- function(., facets = . ~ ., nrows = NULL, ncols = NULL, scales = "fixed") {
    scales <- match.arg(scales, c("fixed", "free_x", "free_y", "free"))
    free <- list(
      x = any(scales %in% c("free_x", "free")),
      y = any(scales %in% c("free_y", "free"))
    )
    
    .$proto(
      facets = as.quoted(facets), free = free, 
      scales = NULL, 
      ncols = ncols, nrows = nrows
    )
  }
  
  conditionals <- function(.) {
    names(.$facets)
  }
  
  # Data shape
  
  initialise <- function(., data) {
    .$shape <- dlply(data[[1]], .$facets, nrow)
    dim(.$shape) <- c(1, length(.$shape))
  }
  
  stamp_data <- function(., data) {
    data.matrix <- dlply(add_group(data), .$facets)
    dim(data.matrix) <- c(1, length(data.matrix))
    data.matrix
  }
  
  # Create grobs for each component of the panel guides
  add_guides <- function(., data, panels_grob, coordinates, theme) {
    n <- length(.$scales$x)
    
    axes_h <- matrix(list(), nrow = 1, ncol = n)
    axes_v <- matrix(list(), nrow = 1, ncol = n)

    for(i in seq_len(n)) {
      axes_h[[1, i]] <- coordinates$guide_axes(.$scales$x[[i]], theme, "bottom")
      axes_v[[1, i]] <- coordinates$guide_axes(.$scales$y[[i]], theme, "left")
    }

    labels <- .$labels_default(.$shape, theme)
    dim(labels) <- c(1, length(labels))

    # Add background and foreground to panels
    panels <- matrix(list(), nrow = 1, ncol = n)
    
    for(i in seq_len(n)) {
      scales <- list(
        x = .$scales$x[[i]], 
        y = .$scales$y[[i]]
      )
      fg <- coordinates$guide_foreground(scales, theme)
      bg <- coordinates$guide_background(scales, theme)

      panels[[1,i]] <- grobTree(bg, panels_grob[[1, i]], fg)
    }
    
    # Arrange 1d structure into a grid -------
    ncols <- .$ncols %||% ceiling(sqrt(n))
    nrows <- .$nrows %||% ceiling(n / ncols)
    stopifnot(nrows * ncols >= n)

    np <- nrows * ncols
    panels <- c(panels, rep(list(nullGrob()), np - n))
    dim(panels) <- c(nrows, ncols)
    labels <- c(labels, rep(list(nullGrob()), np - n))
    dim(labels) <- c(nrows, ncols)

    axes_v <- axes_v[rep(1, nrows), 1, drop = FALSE]
    axes_h <- axes_h[1, rep(1, ncols), drop = FALSE]    
    
    list(
      panel     = panels, 
      axis_v    = axes_v,
      axis_h    = axes_h
      # strip_h   = labels
    )
  }
  
  labels_default <- function(., gm, theme) {
    labels_df <- attr(gm, "split_labels")
    labels <- aaply(labels_df, 1, paste, collapse=", ")

    llply(labels, ggstrip, theme = theme)
  }
  
  create_viewports <- function(., guides, theme) {
    aspect_ratio <- theme$aspect.ratio
    respect <- !is.null(aspect_ratio)
    if (is.null(aspect_ratio)) aspect_ratio <- 1
    
    panel_widths <- rep(unit(1, "null"), ncol(guides$panel))
    panel_heights <- rep(unit(1 * aspect_ratio, "null"), nrow(guides$panel))
    
    widths <- unit.c(
      do.call("max", llply(guides$axis_v, grobWidth)),
      panel_widths
    )
    
    heights <- unit.c(
      # do.call("max", lapply(guides$strip_h, grobHeight)),
      panel_heights,
      do.call("max", llply(guides$axis_h, grobHeight))
    )
    
    layout <- grid.layout(
      ncol = length(widths), widths = widths,
      nrow = length(heights), heights = heights,
      respect = respect
    )
    layout_vp <- viewport(layout=layout, name="panels")
    
    strip_rows <- 0 # nrow(guides$strip_h)
    panel_rows <- nrow(guides$panel)
    panel_cols <- ncol(guides$panel)
    
    children_vp <- do.call("vpList", c(
      # setup_viewports("strip_h", guides$strip_h, c(0,1)),
      
      setup_viewports("axis_v",  guides$axis_v,  c(strip_rows, 0), "off"),
      setup_viewports("panel",   guides$panel,   c(strip_rows, 1)),
      setup_viewports("axis_h",  guides$axis_h, c(strip_rows + panel_rows, 1), "off")
    ))
    
    vpTree(layout_vp, children_vp)
  }

  
  # Position scales ----------------------------------------------------------
  
  position_train <- function(., data, scales) {
    if (is.null(.$scales)) {
      fr <- .$free
      .$scales$x <- scales_list(scales$get_scales("x"), length(.$shape), fr$x)
      .$scales$y <- scales_list(scales$get_scales("y"), length(.$shape), fr$y)
    }

    lapply(data, function(l) {
      for(i in seq_along(.$scales$x)) {
        .$scales$x[[i]]$train_df(l[[1, i]])
        .$scales$y[[i]]$train_df(l[[1, i]])
      }
    })
  }
  
  position_map <- function(., data, scales) {
    lapply(data, function(l) {
      for(i in seq_along(.$scales$x)) {
        l[1, i] <- lapply(l[1, i], function(old) {
          new_x <- .$scales$x[[i]]$map_df(old)
          new_y <- .$scales$y[[i]]$map_df(old)
          
          cbind(
            new_x, 
            new_y,
            old[setdiff(names(old), c(names(new_x), names(new_y)))]
          )
        }) 
      }
      l
    })
  }
  
  make_grobs <- function(., data, layers, cs) {
    lapply(seq_along(data), function(i) {
      layer <- layers[[i]]
      layerd <- data[[i]]
      grobs <- matrix(list(), nrow = nrow(layerd), ncol = ncol(layerd))

      for(i in seq_along(.$scales$x)) {
        scales <- list(
          x = .$scales$x[[i]], 
          y = .$scales$y[[i]]
        )
        grobs[[1, i]] <- layer$make_grob(layerd[[1, i]], scales, cs)
      }
      grobs
    })
  }
  

  # Documentation ------------------------------------------------------------

  objname <- "wrap"
  desc <- "Wrap a 1d ribbon of panels into 2d."
  
  desc_params <- list(
    facets = "",
    margins = "logical value, should marginal rows and columns be displayed"
  )

  
  
  examples <- function(.) {
  }
  
  pprint <- function(., newline=TRUE) {
    cat("facet_", .$objname, "(", .$facets, ", ", .$margins, ")", sep="")
    if (newline) cat("\n")
  }
  
})