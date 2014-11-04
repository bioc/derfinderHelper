derfinderHelper [![Build Status](https://travis-ci.org/lcolladotor/derfinderHelper.svg?branch=master)](https://travis-ci.org/lcolladotor/derfinderHelper)
===============

Helper package for [derfinder](https://github.com/lcolladotor/derfinder).

# Installation instructions

Get R 3.1.1 or newer from [CRAN](http://cran.r-project.org/).

```R
## From Bioconductor
source('http://bioconductor.org/biocLite.R')
biocLite('derfinderHelper')
```

# Vignette

The vignette for this package can be viewed [here](http://lcolladotor.github.io/derfinderHelper/) or via [Bioconductor's website](http://www.bioconductor.org/packages/devel/bioc/html/derfinderHelper.html).


# Citation

Use [derfinder's citation](https://github.com/lcolladotor/derfinder#citation) information.


## Travis CI

This package is automatically tested thanks to [Travis CI](travis-ci.org) and [r-travis](https://github.com/craigcitro/r-travis). If you want to add this to your own package use:

```R
## Use devtools to create the .travis.yml file
library('devtools')
use_travis('yourPackage')

## Read https://github.com/craigcitro/r-travis/wiki to configure .travis.yml appropriately

## Add a status image by following the info at http://docs.travis-ci.com/user/status-images/
```

Testing on R-devel for Bioc-devel is feasible thanks to [r-builder](https://github.com/metacran/r-builder).
