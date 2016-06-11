# IJulia hooks for displaying plots with RCall

# TODO: create a special graphics device. This would allow us to not accidently close devices opened by users, and display plots immediately as they appear.

ijulia_mime = nothing

"""
Set options for R plotting with IJulia.

The first argument should be a MIME object: currently supported are
* `MIME("image/png")` [default]
* `MIME("image/svg+xml")`

The remaining arguments (keyword only) are passed to the appropriate R graphics
device: see the relevant R help for details.
"""
function ijulia_setdevice(m::MIME;kwargs...)
    global ijulia_mime
    rcall(:options,rcalljl_device=rdevicename(m))
    ijulia_mime = m
    nothing
end
ijulia_setdevice(m::MIME"image/png") = ijulia_setdevice(m,width=6*72,height=5*72)
ijulia_setdevice(m::MIME"image/svg+xml") = ijulia_setdevice(m,width=6,height=5)

rdevicename(m::MIME"image/png") = :png
rdevicename(m::MIME"image/svg+xml") = :svg


function ijulia_displayfile(m::MIME"image/png", f)
    open(f) do f
        d = readbytes(f)
        display(Main.IPythonDisplay.InlineDisplay(),m,d)
    end
end
function ijulia_displayfile(m::MIME"image/svg+xml", f)
    # R svg images use named defs, which cause problem when used inline, see
    # https://github.com/jupyter/notebook/issues/333
    # we get around this by renaming the elements.
    open(f) do f
        r = randstring()
        d = readall(f)
        d = replace(d,"id=\"glyph","id=\"glyph"*r)
        d = replace(d,"href=\"#glyph","href=\"#glyph"*r)
        display(Main.IPythonDisplay.InlineDisplay(),m,d)
    end
end

"""
Called after cell evaluation.
Closes graphics device and displays files in notebook.
"""
function ijulia_displayplots()
    if rcopy(Int,"dev.cur()") != 1
        rcopy(Int,"dev.off()")
        for fn in sort(readdir(ijulia_file_dir))
            ffn = joinpath(ijulia_file_dir,fn)
            ijulia_displayfile(ijulia_mime,ffn)
            rm(ffn)
        end
    end
end

# cleanup after error
function ijulia_cleanup()
    if rcopy(Int,"dev.cur()") != 1
        rcopy(Int,"dev.off()")
    end
    for fn in readdir(ijulia_file_dir)
        ffn = joinpath(ijulia_file_dir,fn)
        rm(ffn)
    end
end

function ijulia_init()
    global const ijulia_file_dir = mktempdir()
    ijulia_file_fmt = joinpath(ijulia_file_dir,"rij_%03d")
    rcall(:options,rcalljl_filename=ijulia_file_fmt)

    reval("options(device = function(filename=getOption('rcalljl_filename'),...) getOption('rcalljl_device')(filename,...))")

    Main.IJulia.push_postexecute_hook(ijulia_displayplots)
    Main.IJulia.push_posterror_hook(ijulia_cleanup)
    ijulia_setdevice(MIME"image/png"())
end
