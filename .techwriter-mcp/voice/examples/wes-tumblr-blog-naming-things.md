<!-- Copied verbatim from ~/projects/writing-samples/Wes Roberts/tumblr-blog-naming-things.md (hand-written, per that repo's README). -->

There is a constant struggle we face when “naming things”.

It makes the most sense to order words as we do digits in our numbers (i.e. big-endian, most significant “digits” first). Unfortunately in the English language, adjectives conventionally precede nous (little-endian) and it causes a horrible yet prevalent tendency when writing code to name things such as “initialState” instead of “stateInitial”.

This is a huge problem. It may not seem significant at first, but it is.

Extrapolate for a second and imagine alphabetizing variables:

alphaState
betaState
deltaState
gammaState

Now intermix them with other important information on the same logical level.

afterAuth
alphaState
authInfo
beforeAuth
betaState
deleteEntity
deltaState
getEntity

Wow, it’s a total smorgasbord of names!

If we intelligently normalize our naming scheme, alphabetizing would make sense of our list of various “things”.

authAfter
authBefore
authInfo
entityDelete
entityGet
stateAlpha
stateBeta
stateDelta

Not every language is like English in this way (e.g. Latin or Spanish), so I wonder if those languages bask in the luxury of never having such problems.

As a side note, there is the idea (from 1984, Tim Leary,  and the like) that language informs our reality. I wonder if the little-endianness of our language has any butterfly-effect implications for how we prioritize an urgent task vs an important task.
