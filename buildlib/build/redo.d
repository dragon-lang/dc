module build.redo;
/**

for a target T, check for T.do and fallback to default.do

Example: for "hello.o", check for "hello.o.do", fallback to "default.o.do"

# Database

Redo needs to know where each file is a "source file" or a "target". It saves this information in a metadata file. When redo is asked to build a new file, if it is not in the metadata, then it becomes a "source file" if it already exists and a "target" if it doesn't.

Corner case.  Say that you are mid-way through a redo build and you stop it. Then you delete the redo database.  Then redo determine that what use to be targets are now source files.  So it will never rebuild what was already built when redo ran again after having it's metadata forcibly removed. Just an interesting case to consider. If you remove the redo database, make sure you also remove all the files you want redo to build.

For targets, redo doesn't just use the timestamp to indicate whether they are up-to-date, it also records this information in the metadata (though I'm not sure why).


# How to modify make to be like redo

redo has 2 kinds of rule targets:

"foo.bar", matches "foo.bar", else "default.bar"

so, "foo.bar" matches "foo.bar" or "*.bar"

What about dependencies?

dependencies would be added inside the actions, so instead of a list of dependencies, you would have something like:

-- foo.o
deps foo.c
deps-file foo.deps
cc -o $tmp_target foo.c

--- %.o
deps %.c
deps-file %.deps
cc -o $temp_target %.c


And note that this rule (target and actions) would all be checked if they change to know if foo.o needs to be rebuilt.  This could be saved in the metadata.  Note that is also saves the fact that it depends on any commands that were executed (this might be overkill though).


# Dependencies:

### Method 1:
```
redo-ifchange hello.o
```
Means: the current target depends on "hello.o" (so also make sure hello.o is up-to-date before proceeding)

redo builds the dependencies when this appears in the script

### Method 2:
```
redo-ifcreate hello.o
```
Means: the current target depends on hello.o NOT existing

# More

redo generates files with different names while being generated, i.e.
```
redo-ifchange c
sed 's/World/Waterloo/' < c
```
comparable to
```
a: c
    sed 's/World/Waterloo/' < c > a.tmp
    mv a.tmp a
    fsync
```

# Why multiple files

Allows each build step to depend on it's corresponding `.do` file.  If all rules are in one file then changing one thing in that file means you can't just the timestamp of the Makefile to know what was affected.

Note that a make program could do this by hashing it's rules and automatically making the targets dependent on the rule hashes.

# Timestamps

redo does not use the "newness" of a target to determine it is up-to-date. It uses the metadata in `.redo`, a file in the top-level build directory.

Redo records what happens at each build step, not just isolated pieces of info about each file. (more on this to come)






*/
