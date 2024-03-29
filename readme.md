# What is this?

Since 2023 I have been thinking a lot about the backend architecture for iOS apps and, since then, I have been thinkering a bit: 

The last thing I did was to create a package (still unpublished) that, together with a small dependency injection system, allows my apps to know *nothing* about the database layer (following the repository pattern) besides how to encode/decode the models into a generic representation of an entity.

I was writing *a lot* of boilerplate code for encoding and decoding my models and this bothered me. So when Swift announced macros I saw the opportunity to fix this problem and learn something weird alongside it. This is still a early work and doesn't have the best practices *at all*, but given the... *cof* "minimalist" *cof* documentation on macros, I think it is fine.

## Help me a bit...

I had some trouble setting up this macro package to use the database package and kind of just copy and past'ed the code inside this package, which isn't ideal. I tried to find some documentation for referencing dependencies inside this package but didn't find how to do it. Probably I just looked over it and didn't get it... If you know how to do it, please tell me... Thanks.

# Can I use it?

Make yourself confortable, if you see this being useful for you, do whatever you want with this. Consider giving me credits or referencing my work whenever possible, but, you know, free software and everything...

# Thanks | Obrigado | Danke | Merci
