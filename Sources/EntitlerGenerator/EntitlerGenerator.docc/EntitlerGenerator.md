# ``EntitlerGenerator``

Render typed feature constants from your Entitler catalogue.

## Overview

`swift run entitler generate` writes a file of `Feature` constants. Build tooling can
call the same rendering with ``renderFeatures(_:accessLevel:existingSource:)``.

## Topics

### Rendering

- ``renderFeatures(_:accessLevel:existingSource:)``
- ``featureConstantName(for:)``
- ``existingFeatureNames(in:)``
- ``featureNameInitialisms``
- ``AccessLevel``

### Command line

- ``GeneratorCommand``
