-- v0.8.6 Color Precision: READ-ONLY, no touch or OCR.
-- Verify coordinates from nk.screen() first; physical screenshot pixels.
local nk=require("nktouch_v7")
local geometry=nk.screen()
print("[NKPRECISION] screen="..tostring(geometry))
local points={
  {x=100,y=120,r=255,g=255,b=255,tolerance=12},
  {x=110,y=120,r=255,g=255,b=255,tolerance=12}
}
local result,err,code=nk.precisionInspect({points=points})
if not result then
  print("[NKPRECISION][FAIL] "..tostring(code)..": "..tostring(err))
  return
end
print(("[NKPRECISION][COLOR] matched=%s points=%d/%d frame_count=%d geometry=%s"):format(
  tostring(result.matched),result.matches,result.total,
  result.frame_count,tostring(result.geometry_verified)))
-- A pattern match at one instant does not prove all UI animations stopped.
