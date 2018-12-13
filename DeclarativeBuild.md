


Rule:

// Maybe use HJSON format?

For dmd specifics:
Take a look at: https://github.com/marler8997/dmd/blob/f8916a3d6f89dfe8ff83abe25199968991251ec2/src/dmd.bm

{
  optabgen: {
    outputType: exe
    betterC: true
    versions: [
      MARS
    ]
    sources: [
      dmd/backend/optabgen.d
    ]
 }
}


Then each tool will have a way of taking that input and creating dependencies and actions:

{
 dmd: {
  flags: {
    betterC: "-betterC"
  }
  args: [
    "$sources"
    "-version=$versions"
  ]
  enums: [
    outputType: {
      exe: null
      lib: {
        args: ["-lib"]
      }
    }
  ]
 }
}

Need a way to get dependencies as well.  Could make arguments to them and/or get them from the generated json file.
