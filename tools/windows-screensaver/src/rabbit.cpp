/*
 * MTGPU rabbit screensaver for Windows.
 *
 * Abstract navy background (same artwork as the Linux/macOS savers) with the
 * four-colour rabbit wandering over it.  The rabbit cycles through the four
 * ksplash frames every 700 ms (one coloured corner at a time), scaled to 12.5%
 * of the screen width, with a rounded alpha mask.
 *
 * Command line: /s run (default), /c configure, /p <hwnd> preview (ignored).
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <objidl.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>

using namespace Gdiplus;

#define FRAME_COUNT 4
#define FRAME_MS 700
#define TICK_MS 30
#define ID_TICK 1
#define ID_FRAME 2
#define RES_BG 200
#define RES_FRAME0 201

static const wchar_t kClass[] = L"MtGpuRabbitSaver";

static Bitmap *g_bgImage;
static Bitmap *g_frameImage[FRAME_COUNT];
static HBITMAP g_frames[FRAME_COUNT];
static HDC g_bgDC;
static HBITMAP g_bgBitmap;
static int g_frameW, g_frameH;
static int g_frame;

static RECT g_screen;       /* virtual screen in screen coords */
static int g_size;          /* on-screen rabbit edge */
static double g_cx, g_cy;   /* rabbit centre, client coords */
static double g_vx, g_vy;
static double g_tx, g_ty;   /* wander target, centre coords */
static RECT g_dirty;
static HDC g_scratchDC;
static HBITMAP g_scratchBmp;
static int g_scratchW, g_scratchH;
static POINT g_startMouse;
static DWORD g_startTick;
static int g_mouseArmed;

static double frand(void)
{
    return (double)rand() / (double)RAND_MAX;
}

static Bitmap *load_png_resource(int id)
{
    HRSRC res = FindResourceW(NULL, MAKEINTRESOURCEW(id), RT_RCDATA);
    if (!res)
        return NULL;
    DWORD size = SizeofResource(NULL, res);
    void *data = LockResource(LoadResource(NULL, res));
    if (!data || !size)
        return NULL;

    HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, size);
    if (!mem)
        return NULL;
    void *dst = GlobalLock(mem);
    memcpy(dst, data, size);
    GlobalUnlock(mem);

    IStream *stream = NULL;
    if (CreateStreamOnHGlobal(mem, TRUE, &stream) != S_OK) {
        GlobalFree(mem);
        return NULL;
    }
    Bitmap *bmp = Bitmap::FromStream(stream);
    stream->Release();
    return bmp;
}

/* Convert an ARGB GDI+ bitmap into a premultiplied 32bpp top-down DIB section
 * suitable for AlphaBlend(). */
static HBITMAP to_premultiplied_dib(Bitmap *src, int *outW, int *outH)
{
    if (!src || src->GetLastStatus() != Ok)
        return NULL;
    int w = (int)src->GetWidth(), h = (int)src->GetHeight();
    Rect rect(0, 0, w, h);
    BitmapData bd;
    if (src->LockBits(&rect, ImageLockModeRead, PixelFormat32bppARGB, &bd) != Ok)
        return NULL;

    BITMAPINFO bi = {0};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h; /* top-down */
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    void *bits = NULL;
    HBITMAP dib = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!dib) {
        src->UnlockBits(&bd);
        return NULL;
    }

    const BYTE *row = (const BYTE *)bd.Scan0;
    BYTE *dst = (BYTE *)bits;
    for (int y = 0; y < h; y++) {
        const BYTE *s = row + (size_t)y * bd.Stride;
        BYTE *d = dst + (size_t)y * w * 4;
        for (int x = 0; x < w; x++) {
            BYTE a = s[3];
            d[0] = (BYTE)((s[0] * a + 127) / 255); /* B */
            d[1] = (BYTE)((s[1] * a + 127) / 255); /* G */
            d[2] = (BYTE)((s[2] * a + 127) / 255); /* R */
            d[3] = a;
            s += 4;
            d += 4;
        }
    }
    src->UnlockBits(&bd);
    *outW = w;
    *outH = h;
    return dib;
}

static int load_assets(void)
{
    g_bgImage = load_png_resource(RES_BG);
    if (!g_bgImage || g_bgImage->GetLastStatus() != Ok)
        return 0;

    for (int i = 0; i < FRAME_COUNT; i++) {
        g_frameImage[i] = load_png_resource(RES_FRAME0 + i);
        if (!g_frameImage[i] || g_frameImage[i]->GetLastStatus() != Ok)
            return 0;
        g_frames[i] = to_premultiplied_dib(g_frameImage[i], &g_frameW, &g_frameH);
        if (!g_frames[i])
            return 0;
    }
    return 1;
}

/* Copy an ARGB GDI+ bitmap into a plain 32bpp top-down DIB (alpha ignored). */
static HBITMAP to_dib_straight(Bitmap *src, int *outW, int *outH)
{
    if (!src || src->GetLastStatus() != Ok)
        return NULL;
    int w = (int)src->GetWidth(), h = (int)src->GetHeight();
    Rect rect(0, 0, w, h);
    BitmapData bd;
    if (src->LockBits(&rect, ImageLockModeRead, PixelFormat32bppARGB, &bd) != Ok)
        return NULL;

    BITMAPINFO bi = {0};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    void *bits = NULL;
    HBITMAP dib = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!dib) {
        src->UnlockBits(&bd);
        return NULL;
    }
    const BYTE *row = (const BYTE *)bd.Scan0;
    BYTE *dst = (BYTE *)bits;
    for (int y = 0; y < h; y++)
        memcpy(dst + (size_t)y * w * 4, row + (size_t)y * bd.Stride, (size_t)w * 4);
    src->UnlockBits(&bd);
    *outW = w;
    *outH = h;
    return dib;
}

/* Scale the background once into a screen-sized DIB, so per-frame redraws are
 * plain BitBlt operations. */
static int build_background_cache(int w, int h)
{
    int bgW = 0, bgH = 0;
    HBITMAP bgSrc = to_dib_straight(g_bgImage, &bgW, &bgH);
    if (!bgSrc)
        return 0;

    BITMAPINFO bi = {0};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    void *bits = NULL;
    g_bgBitmap = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!g_bgBitmap) {
        DeleteObject(bgSrc);
        return 0;
    }
    g_bgDC = CreateCompatibleDC(NULL);
    HDC srcDC = CreateCompatibleDC(NULL);
    HGDIOBJ oldDst = SelectObject(g_bgDC, g_bgBitmap);
    HGDIOBJ oldSrc = SelectObject(srcDC, bgSrc);
    SetStretchBltMode(g_bgDC, HALFTONE);
    SetBrushOrgEx(g_bgDC, 0, 0, NULL);
    StretchBlt(g_bgDC, 0, 0, w, h, srcDC, 0, 0, bgW, bgH, SRCCOPY);
    SelectObject(srcDC, oldSrc);
    /* keep the screen-sized bitmap selected in g_bgDC: copy_background BitBlts from it */
    (void)oldDst;
    DeleteDC(srcDC);
    DeleteObject(bgSrc);
    return 1;
}

static void pick_target(void)
{
    int w = g_screen.right - g_screen.left;
    int h = g_screen.bottom - g_screen.top;
    double margin = g_size * 0.6;
    g_tx = margin + frand() * (w - 2 * margin);
    g_ty = margin + frand() * (h - 2 * margin);
}

static void copy_background(HDC hdc, int x, int y, int w, int h, int srcX, int srcY)
{
    if (!g_bgDC || w <= 0 || h <= 0)
        return;
    BitBlt(hdc, x, y, w, h, g_bgDC, srcX, srcY, SRCCOPY);
}

static void draw_rabbit(HDC hdc, int x, int y)
{
    HBITMAP frame = g_frames[g_frame];
    if (!frame)
        return;
    HDC mem = CreateCompatibleDC(hdc);
    HGDIOBJ old = SelectObject(mem, frame);
    BLENDFUNCTION bf = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    AlphaBlend(hdc, x, y, g_size, g_size, mem, 0, 0, g_frameW, g_frameH, bf);
    SelectObject(mem, old);
    DeleteDC(mem);
}

static void ensure_scratch(int w, int h)
{
    if (g_scratchDC && g_scratchW >= w && g_scratchH >= h)
        return;
    if (g_scratchDC) {
        DeleteDC(g_scratchDC);
        DeleteObject(g_scratchBmp);
    }
    BITMAPINFO bi = {0};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void *bits = NULL;
    g_scratchBmp = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
    g_scratchDC = CreateCompatibleDC(NULL);
    SelectObject(g_scratchDC, g_scratchBmp);
    g_scratchW = w;
    g_scratchH = h;
}

/* Compose the target rectangle off-screen (background + rabbit) and blit it in
 * one operation, so the erase and the redraw can never be seen separately. */
static void compose_and_blit(HWND hwnd, const RECT *rc)
{
    int w = rc->right - rc->left;
    int h = rc->bottom - rc->top;
    if (w <= 0 || h <= 0)
        return;
    ensure_scratch(w, h);
    copy_background(g_scratchDC, 0, 0, w, h, rc->left, rc->top);
    draw_rabbit(g_scratchDC, g_dirty.left - rc->left, g_dirty.top - rc->top);
    HDC hdc = GetDC(hwnd);
    BitBlt(hdc, rc->left, rc->top, w, h, g_scratchDC, 0, 0, SRCCOPY);
    ReleaseDC(hwnd, hdc);
    /* sync with the DWM composition pass: avoids the GDI blit racing the
     * desktop compositor (tearing / shimmer at high resolutions) */
    DwmFlush();
}

static RECT union_rect(const RECT *a, const RECT *b)
{
    RECT r;
    r.left = a->left < b->left ? a->left : b->left;
    r.top = a->top < b->top ? a->top : b->top;
    r.right = a->right > b->right ? a->right : b->right;
    r.bottom = a->bottom > b->bottom ? a->bottom : b->bottom;
    return r;
}

static void step(HWND hwnd)
{
    RECT prev = g_dirty;
    const double dt = TICK_MS / 1000.0;
    double w = g_screen.right - g_screen.left;
    double speed = w / 9.0;

    double dx = g_tx - g_cx, dy = g_ty - g_cy;
    double dist = sqrt(dx * dx + dy * dy);
    if (dist < g_size * 0.25) {
        pick_target();
        dx = g_tx - g_cx;
        dy = g_ty - g_cy;
        dist = sqrt(dx * dx + dy * dy);
    }
    double desiredX = dist > 0.001 ? dx / dist * speed : 0;
    double desiredY = dist > 0.001 ? dy / dist * speed : 0;
    g_vx += (desiredX - g_vx) * 0.08;
    g_vy += (desiredY - g_vy) * 0.08;
    g_cx += g_vx * dt;
    g_cy += g_vy * dt;

    /* keep the sprite fully on screen */
    double half = g_size / 2.0;
    if (g_cx < half) { g_cx = half; g_vx = fabs(g_vx); pick_target(); }
    if (g_cy < half) { g_cy = half; g_vy = fabs(g_vy); pick_target(); }
    if (g_cx > w - half) { g_cx = w - half; g_vx = -fabs(g_vx); pick_target(); }
    if (g_cy > g_screen.bottom - g_screen.top - half) {
        g_cy = g_screen.bottom - g_screen.top - half;
        g_vy = -fabs(g_vy);
        pick_target();
    }

    g_dirty.left = (LONG)(g_cx - half);
    g_dirty.top = (LONG)(g_cy - half);
    g_dirty.right = g_dirty.left + g_size;
    g_dirty.bottom = g_dirty.top + g_size;

    RECT u = union_rect(&prev, &g_dirty);
    compose_and_blit(hwnd, &u);
}

static void exit_saver(HWND hwnd)
{
    ShowCursor(TRUE);
    DestroyWindow(hwnd);
    PostQuitMessage(0);
}

static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE: {
        int w = g_screen.right - g_screen.left;
        int h = g_screen.bottom - g_screen.top;
        g_size = (int)(w * 0.125);
        if (g_size > g_frameW)
            g_size = g_frameW;
        if (g_size < 96)
            g_size = 96;
        g_frame = 0;
        g_cx = w / 2.0;
        g_cy = h / 2.0;
        g_vx = g_vy = 0;
        pick_target();
        g_dirty.left = (LONG)(g_cx - g_size / 2.0);
        g_dirty.top = (LONG)(g_cy - g_size / 2.0);
        g_dirty.right = g_dirty.left + g_size;
        g_dirty.bottom = g_dirty.top + g_size;
        SetTimer(hwnd, ID_TICK, TICK_MS, NULL);
        SetTimer(hwnd, ID_FRAME, FRAME_MS, NULL);
        SetCursor(NULL);
        return 0;
    }

    case WM_TIMER:
        if (wp == ID_TICK)
            step(hwnd);
        else if (wp == ID_FRAME)
            g_frame = (g_frame + 1) % FRAME_COUNT;
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rc = ps.rcPaint;
        if (IsRectEmpty(&rc))
            GetClientRect(hwnd, &rc);
        ensure_scratch(rc.right - rc.left, rc.bottom - rc.top);
        copy_background(g_scratchDC, 0, 0, rc.right - rc.left, rc.bottom - rc.top,
                        rc.left, rc.top);
        draw_rabbit(g_scratchDC, g_dirty.left - rc.left, g_dirty.top - rc.top);
        BitBlt(hdc, rc.left, rc.top, rc.right - rc.left, rc.bottom - rc.top,
               g_scratchDC, 0, 0, SRCCOPY);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_SETCURSOR:
        SetCursor(NULL);
        return TRUE;

    case WM_MOUSEMOVE: {
        POINT p;
        GetCursorPos(&p);
        if (!g_mouseArmed) {
            if (GetTickCount() - g_startTick > 600)
                g_mouseArmed = 1;
            g_startMouse = p;
            return 0;
        }
        if (abs(p.x - g_startMouse.x) > 4 || abs(p.y - g_startMouse.y) > 4)
            exit_saver(hwnd);
        return 0;
    }

    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_MOUSEWHEEL:
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
        exit_saver(hwnd);
        return 0;

    case WM_CLOSE:
        exit_saver(hwnd);
        return 0;

    case WM_DESTROY:
        KillTimer(hwnd, ID_TICK);
        KillTimer(hwnd, ID_FRAME);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static int run_saver(void)
{
    srand((unsigned)time(NULL) ^ GetTickCount());
    if (!load_assets()) {
        MessageBoxW(NULL, L"Could not load screensaver assets.", L"MTGPU Rabbit", MB_ICONERROR);
        return 1;
    }

    g_screen.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    g_screen.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    g_screen.right = g_screen.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    g_screen.bottom = g_screen.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);

    int w = g_screen.right - g_screen.left;
    int h = g_screen.bottom - g_screen.top;
    if (!build_background_cache(w, h)) {
        MessageBoxW(NULL, L"Could not prepare the background.", L"MTGPU Rabbit", MB_ICONERROR);
        return 1;
    }

    /* Per-monitor DPI aware: otherwise Windows bitmap-stretches the 6K output
     * when display scaling is not 100%, which looks soft and can flicker. */
    {
        HMODULE user32 = GetModuleHandleW(L"user32.dll");
        typedef BOOL (WINAPI *SetDpiCtx)(HANDLE);
        SetDpiCtx setCtx = user32 ? (SetDpiCtx)GetProcAddress(user32, "SetProcessDpiAwarenessContext") : NULL;
        if (setCtx)
            setCtx((HANDLE)-4); /* PER_MONITOR_AWARE_V2 */
        else
            SetProcessDPIAware();
    }

    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = wnd_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hCursor = NULL;
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = kClass;
    if (!RegisterClassExW(&wc))
        return 1;

    HWND hwnd = CreateWindowExW(WS_EX_TOPMOST, kClass, L"MTGPU Rabbit",
                                WS_POPUP | WS_VISIBLE,
                                g_screen.left, g_screen.top, w, h,
                                NULL, NULL, wc.hInstance, NULL);
    if (!hwnd)
        return 1;

    ShowCursor(FALSE);
    SetCursor(NULL);
    SetFocus(hwnd);
    g_startTick = GetTickCount();
    g_mouseArmed = 0;
    GetCursorPos(&g_startMouse);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmdline, int show)
{
    (void)inst; (void)prev; (void)cmdline; (void)show;

    GdiplusStartupInput gsi;
    ULONG_PTR token = 0;
    GdiplusStartup(&token, &gsi, NULL);

    int argc = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    int mode = 's';
    for (int i = 1; argv && i < argc; i++) {
        if (argv[i][0] == L'/' || argv[i][0] == L'-') {
            wchar_t c = argv[i][1];
            if (c == L'c' || c == L'C')
                mode = 'c';
            else if (c == L'p' || c == L'P')
                mode = 'p';
        }
    }
    if (argv)
        LocalFree(argv);

    if (mode == 'c') {
        MessageBoxW(NULL,
                    L"MTGPU 兔头屏保\n\n"
                    L"四色兔头在 abstract 背景上四处游走，每 700ms 切换一次颜色。\n\n"
                    L"安装：右键 rabbit.scr → 安装。\n"
                    L"退出：移动鼠标或按任意键。",
                    L"MTGPU Rabbit", MB_ICONINFORMATION);
        GdiplusShutdown(token);
        return 0;
    }
    if (mode == 'p') {
        GdiplusShutdown(token);
        return 0;
    }

    int rc = run_saver();
    GdiplusShutdown(token);
    return rc;
}
