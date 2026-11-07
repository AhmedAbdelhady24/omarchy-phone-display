.pragma library

function luminance(color) {
    function linear(value) { return value <= 0.04045 ? value/12.92 : Math.pow((value+0.055)/1.055,2.4) }
    return 0.2126*linear(color.r)+0.7152*linear(color.g)+0.0722*linear(color.b)
}
function contrast(a,b) {
    var light=luminance(a), dark=luminance(b)
    return (Math.max(light,dark)+0.05)/(Math.min(light,dark)+0.05)
}
function inkFor(color) {
    return contrast(color,{r:0,g:0,b:0}) >= contrast(color,{r:1,g:1,b:1}) ? "#000000" : "#ffffff"
}
