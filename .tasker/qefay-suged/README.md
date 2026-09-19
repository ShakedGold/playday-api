---
status: open
priority: 60
kind: feature
tags:
    - db
    - refactor
---

# Switch to a NoSQL db

Because our current implementation of extra library data (for example the steam id) is stored in a tagged union, we cannot have a schema that fits all of the tagged union's fields
Some will have X, some will have Y.

So we need a more flexible DB storage method, like NoSQL, because we can just not define the schema there for the library data and it should just work.

> Make sure to research the best NoSQL solution for this project and find libraries in zig that work with it.
