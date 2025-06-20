# mediawiki-el-search
The start of a search mode for mediawiki.el

Broadly something like this

```
(use-package mediawiki-el-search)
```

Then you can `M-x mediawiki-search-for-titles-to-buffer` and it'll pop
up a buffer called `*mediawiki-pages*` formatted so you can use
`mediawiki-open-page-at-point` on each one.

There's also a couple of other functions like
`mediawiki-search-for-titles` that just returns a list of page titles
and `mediawiki-search-for-titles-by-text` that searches pages text
instead of just titles.

Because the original mediawiki.el uses XML formatted queries and those
are deprecated this does kinda roll its own with
`mediawiki-api-call-json` that returns hashmaps of the results, the
general `mediawiki-search` function does all the necessary query
construction and paging of results for you.

There's probably loads of bugs, this is a fun afternoon/evenings hackery.