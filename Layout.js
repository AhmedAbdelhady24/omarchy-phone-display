.pragma library

function validMonitors(monitors) {
    return (monitors || []).filter(function(m) {
        return m.name !== "PHONE-DISPLAY" && [m.x, m.y, m.width, m.height].every(function(n) { return typeof n === "number" && isFinite(n) }) && m.width > 0 && m.height > 0
    }).slice(0, 32)
}
function phoneSize(settings, nativeSize, current, observedOrientation) {
    var res = settings.resolution || "native"
    var size = (res === "native" ? nativeSize || "1080x2400" : res).split("x").map(Number)
    var orientation = settings.orientation || "auto"
    if (orientation === "auto" && current) size = current.split("@")[0].split("x").map(Number)
    else {
    if (orientation === "auto") orientation = observedOrientation || "portrait"
    if ((orientation === "landscape" && size[0] < size[1]) || (orientation === "portrait" && size[0] > size[1])) size.reverse()
    }
    var scale = Number(settings.scale || "1.5")
    return {width: Math.round(size[0] / scale), height: Math.round(size[1] / scale)}
}
function locate(monitors, phone, placement) {
    var match = /^(-?\d+)x(-?\d+)$/.exec(placement || "")
    if (match) return {x: Number(match[1]), y: Number(match[2])}
    if (!monitors.length) return {x: 0, y: 0}
    var sorted = monitors.slice().sort(function(a,b) { return placement === "left-of" ? a.x-b.x : (b.x+b.width)-(a.x+a.width) })
    return {x: placement === "left-of" ? sorted[0].x-phone.width : sorted[0].x+sorted[0].width, y: sorted[0].y}
}
function overlaps(a, b) {
    return a.x < b.x+b.width && a.x+a.width > b.x && a.y < b.y+b.height && a.y+a.height > b.y
}
function snap(monitors, phone, x, y) {
    var candidates = []
    function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)) }
    monitors.forEach(function(m) {
        var cy = clamp(y, m.y-phone.height+1, m.y+m.height-1)
        var cx = clamp(x, m.x-phone.width+1, m.x+m.width-1)
        // Snap aligned edges/centres when the pointer is within 80 logical px.
        function nearest(n, values) {
            var best=n, distance=80
            values.forEach(function(v) { if (Math.abs(n-v)<distance) { best=v; distance=Math.abs(n-v) } })
            return best
        }
        cy=nearest(cy,[m.y,m.y+m.height-phone.height,m.y+(m.height-phone.height)/2])
        cx=nearest(cx,[m.x,m.x+m.width-phone.width,m.x+(m.width-phone.width)/2])
        candidates.push({x: m.x-phone.width, y: cy}, {x: m.x+m.width, y: cy}, {x: cx, y: m.y-phone.height}, {x: cx, y: m.y+m.height})
    })
    candidates = candidates.filter(function(p) { return !monitors.some(function(m) { return overlaps({x:p.x,y:p.y,width:phone.width,height:phone.height},m) }) })
    candidates.sort(function(a,b) { return Math.pow(a.x-x,2)+Math.pow(a.y-y,2)-Math.pow(b.x-x,2)-Math.pow(b.y-y,2) })
    var best = candidates[0] || {x:x,y:y}
    return {x:Math.round(best.x),y:Math.round(best.y)}
}
function scene(monitors, phone, placement) {
    var pos = locate(monitors, phone, placement)
    var all = monitors.concat([{x:pos.x,y:pos.y,width:phone.width,height:phone.height}])
    var x = Math.min.apply(null, all.map(function(m) { return m.x })), y = Math.min.apply(null, all.map(function(m) { return m.y }))
    return {x:x,y:y,width:Math.max.apply(null,all.map(function(m) { return m.x+m.width }))-x,
        height:Math.max.apply(null,all.map(function(m) { return m.y+m.height }))-y,phone:pos}
}
