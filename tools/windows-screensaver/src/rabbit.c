/*
 * MTGPU rabbit screensaver for Windows.
 *
 * A four-colour rabbit (the same four frames as the Plymouth/ksplash theme)
 * wanders around a black screen and cycles through its four colour phases.
 *
 * Command line: /s run (default), /c configure (message box), /p <hwnd> preview
 * (not supported, returns immediately).
 *
 * Build with x86_64-w64-mingw32-gcc; see build.sh.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>

#define FRAME_COUNT 4
#define FRAME_MS 700
#define TICK_MS 30
#define ID_TICK 1
#define ID_FRAME 2

static const wchar_t kClass[] = L"MtGpuRabbitSaver";

static HBITMAP g_frames[FRAME_COUNT];
static int g_frameW, g_frameH;
static int g_frame;

static RECT g_screen;   /* virtual screen, in screen coordinates */
static int g_x, g_y;    /* top-left of the rabbit, window coordinates */
static int g_size;
static double g_dx, g_dy;
static int g_dirTicks, g_dirLeft;
static RECT g_dirty;    /* previous rabbit rect, to erase cheaply */
static POINT g_startMouse;
static DWORD g_startTick;
static int g_mouseArmed;

static double frand(void)
{
    return (double)rand() / (double)RAND_MAX;
}

static void random_direction(void)
{
    double a = frand() * 6.283185307179586;
    double speed = (double)g_size / 38.0;
    if (speed < 4.0)
        speed = 4.0;
    g_dx = cos(a) * speed;
    g_dy = sin(a) * speed;
    g_dirTicks = 40 + (int)(frand() * 90); /* ~1.2-4 s at 30 ms */
    g_dirLeft = g_dirTicks;
}

static void load_frames(void)
{
    for (int i = 0; i < FRAME_COUNT; i++) {
        g_frames[i] = (HBITMAP)LoadImageW(GetModuleHandleW(NULL),
                                          MAKEINTRESOURCEW(101 + i),
                                          IMAGE_BITMAP, 0, 0,
                                          LR_CREATEDIBSECTION);
    }
    if (!g_frames[0])
        return;
    BITMAP bm;
    GetObjectW(g_frames[0], sizeof(bm), &bm);
    g_frameW = bm.bmWidth;
    g_frameH = bm.bmHeight;
}

static void draw_rabbit(HDC hdc, int x, int y)
{
    HBITMAP frame = g_frames[g_frame];
    if (!frame)
        return;
    HDC mem = CreateCompatibleDC(hdc);
    HGDIOBJ old = SelectObject(mem, frame);
    SetStretchBltMode(hdc, HALFTONE);
    SetBrushOrgEx(hdc, 0, 0, NULL);
    StretchBlt(hdc, x, y, g_size, g_size, mem, 0, 0, g_frameW, g_frameH, SRCCOPY);
    SelectObject(mem, old);
    DeleteDC(mem);
}

static void erase_dirty(HWND hwnd)
{
    if (IsRectEmpty(&g_dirty))
        return;
    HDC hdc = GetDC(hwnd);
    HBRUSH black = (HBRUSH)GetStockObject(BLACK_BRUSH);
    FillRect(hdc, &g_dirty, black);
    ReleaseDC(hwnd, hdc);
}

static void clamp_position(void)
{
    int w = g_screen.right - g_screen.left;
    int h = g_screen.bottom - g_screen.top;

    if (g_x < 0) { g_x = 0; g_dx = -g_dx; random_direction(); }
    if (g_y < 0) { g_y = 0; g_dy = -g_dy; random_direction(); }
    if (g_x + g_size > w) { g_x = w - g_size; g_dx = -g_dx; random_direction(); }
    if (g_y + g_size > h) { g_y = h - g_size; g_dy = -g_dy; random_direction(); }
    if (g_x < 0) g_x = 0;
    if (g_y < 0) g_y = 0;
}

static void step(HWND hwnd)
{
    RECT old = g_dirty;

    g_x += (int)(g_dx + (g_dx > 0 ? 0.5 : -0.5));
    g_y += (int)(g_dy + (g_dy > 0 ? 0.5 : -0.5));
    clamp_position();
    if (--g_dirLeft <= 0)
        random_direction();

    g_dirty.left = g_x;
    g_dirty.top = g_y;
    g_dirty.right = g_x + g_size;
    g_dirty.bottom = g_y + g_size;

    HDC hdc = GetDC(hwnd);
    HBRUSH black = (HBRUSH)GetStockObject(BLACK_BRUSH);
    /* erase the old rect, then the part of the new rect that does not overlap */
    FillRect(hdc, &old, black);
    if (!EqualRect(&old, &g_dirty)) {
        RECT r = g_dirty;
        /* erase new-rect minus old-rect, in up to four bands */
        RECT bands[4];
        int n = 0;
        bands[n++] = (RECT){ r.left, r.top, r.right, old.top };
        bands[n++] = (RECT){ r.left, old.bottom, r.right, r.bottom };
        bands[n++] = (RECT){ r.left, old.top, old.left, old.bottom };
        bands[n++] = (RECT){ old.right, old.top, r.right, old.bottom };
        for (int i = 0; i < n; i++)
            if (!IsRectEmpty(&bands[i]))
                FillRect(hdc, &bands[i], black);
    }
    draw_rabbit(hdc, g_x, g_y);
    ReleaseDC(hwnd, hdc);
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
    case WM_CREATE:
        SetTimer(hwnd, ID_TICK, TICK_MS, NULL);
        SetTimer(hwnd, ID_FRAME, FRAME_MS, NULL);
        g_frame = 0;
        g_x = (g_screen.right - g_screen.left - g_size) / 2;
        g_y = (g_screen.bottom - g_screen.top - g_size) / 2;
        g_dirty.left = g_x; g_dirty.top = g_y;
        g_dirty.right = g_x + g_size; g_dirty.bottom = g_y + g_size;
        random_direction();
        SetCursor(NULL);
        return 0;

    case WM_TIMER:
        if (wp == ID_TICK) {
            step(hwnd);
        } else if (wp == ID_FRAME) {
            g_frame = (g_frame + 1) % FRAME_COUNT;
            /* redraw immediately so the colour change is visible while moving */
            erase_dirty(hwnd);
            g_dirty.left = g_x; g_dirty.top = g_y;
            g_dirty.right = g_x + g_size; g_dirty.bottom = g_y + g_size;
            HDC hdc = GetDC(hwnd);
            draw_rabbit(hdc, g_x, g_y);
            ReleaseDC(hwnd, hdc);
        }
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rc;
        GetClientRect(hwnd, &rc);
        FillRect(hdc, &rc, (HBRUSH)GetStockObject(BLACK_BRUSH));
        draw_rabbit(hdc, g_x, g_y);
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
    load_frames();
    if (!g_frames[0]) {
        MessageBoxW(NULL, L"Could not load rabbit frames.", L"MTGPU Rabbit", MB_ICONERROR);
        return 1;
    }

    g_screen.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    g_screen.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    g_screen.right = g_screen.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    g_screen.bottom = g_screen.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);

    int w = g_screen.right - g_screen.left;
    int h = g_screen.bottom - g_screen.top;
    g_size = h / 5;
    if (g_size > g_frameW)
        g_size = g_frameW;
    if (g_size < 120)
        g_size = 120;

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
                    L"四色兔头在黑色背景上四处游走，每 700ms 切换一次颜色。\n\n"
                    L"安装：右键 rabbit.scr → 安装。\n"
                    L"退出：移动鼠标或按任意键。",
                    L"MTGPU Rabbit", MB_ICONINFORMATION);
        return 0;
    }
    if (mode == 'p')
        return 0; /* preview mode not supported */

    return run_saver();
}
