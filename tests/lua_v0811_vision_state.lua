local vision=dofile("lua/nkvision_state.lua")
local function expect(ok,msg) if not ok then error(msg or "assertion failed",2) end end
do
  local normalized,err,code=vision.normalize("Nhập tên để tạo Tài khoản Meta")
  expect(normalized=="nhaptendetaotaikhoanmeta","Vietnamese normalization "..tostring(err or code))
end
local function fixture(texts)
  local now,index=0,0
  local nk={
    screen=function() return "750;;1334" end,
    ocr=function() index=math.min(index+1,#texts); return texts[index] end
  }
  return nk,function(ms) now=now+ms; return true end,function() return now end,
    function() return index end
end
do
  local nk,sleep,clock,reads=fixture({"Nhập tên để tạo tài khoản","Nhập tên để tạo tài khoản"})
  local result,err,code=vision.waitFor(nk,{x=0,y=0,w=750,h=1334,
    labels={name_form={"nhap ten de tao tai khoan"}},
    stable_reads=2,max_reads=4,interval_ms=100,timeout_ms=1000,
    sleep=sleep,now=clock})
  expect(result and result.state=="name_form","stable OCR state "..tostring(code or err))
  expect(result.reads==2 and reads()==2,"bounded read count")
  expect(result.ocr_text_included==false,"raw OCR is not returned")
end
do
  local nk,sleep,clock=fixture({"Nhập tên để tạo tài khoản","Đăng nhập"})
  local result,_,code,detail=vision.waitFor(nk,{x=0,y=0,w=750,h=1334,
    labels={name_form={"nhap ten de tao tai khoan"},login={"dang nhap"}},
    stable_reads=2,max_reads=3,interval_ms=100,timeout_ms=1000,
    sleep=sleep,now=clock})
  expect(result==nil and code=="STATE_UNCERTAIN","unstable state fails closed")
  expect(detail.ocr_text_included==false,"no OCR text in failure detail")
end
print("[NKVISION811][HOST] PASS")
