#include <windows.h>
#include <gdiplus.h>
#include <vector>
#include <string>
#include <cstdlib>

#pragma comment (lib,"Gdiplus.lib")
#pragma comment (lib,"user32.lib")
#pragma comment (lib,"gdi32.lib")

using namespace Gdiplus;

// --- Physics State ---
float birdY = 300.0f;
float birdVelocity = 0.0f;
float gravity = 0.4f;
float jumpStrength = -6.5f; // slightly stronger for smoother feel
float birdX = 100.0f;

int score = 0;
int highScore = 0;
bool gameOver = false;
bool playing = false;
bool jumpRequested = false;

struct Pipe {
    float x;
    float gapY;
    float gapSize;
    bool scored;
};

std::vector<Pipe> pipes;

void InitGame() {
    birdY = 300.0f;
    birdVelocity = 0.0f;
    score = 0;
    gameOver = false;
    playing = false;
    jumpRequested = false;
    pipes.clear();
    pipes.push_back({ 800.0f, 200.0f, 150.0f, false });
}

// Inline assembly physics update
void UpdatePhysicsAsm() {
    __asm {
        mov al, byte ptr [gameOver]
        test al, al
        jnz physics_end
        
        mov al, byte ptr [playing]
        test al, al
        jz physics_end
        
        mov al, byte ptr [jumpRequested]
        test al, al
        jz apply_gravity
        
        fld dword ptr [jumpStrength]
        fstp dword ptr [birdVelocity]
        mov byte ptr [jumpRequested], 0
        
    apply_gravity:
        fld dword ptr [birdVelocity]
        fadd dword ptr [gravity]
        fst dword ptr [birdVelocity] 
        
        fadd dword ptr [birdY]
        fstp dword ptr [birdY]       
        
        fld dword ptr [birdY]
        ftst
        fstsw ax
        sahf
        ja check_floor 
        
        fldz
        fstp dword ptr [birdY]
        
    check_floor:
        fstp st(0) 
        
    physics_end:
    }
}

// Inline assembly collision detection
void CheckCollisionAsm(float pipeX, float pipeGapY, float pipeGapSize) {
    float birdSize = 44.0f; // increased visual hitbox corresponding to larger bird
    float pipeWidth = 64.0f; // slightly wider to account for pipe caps
    float floorY = 550.0f;
    
    __asm {
        mov al, byte ptr [gameOver]
        test al, al
        jnz coll_end
        
        fld dword ptr [birdY]
        fadd dword ptr [birdSize]
        fcomp dword ptr [floorY]
        fstsw ax
        sahf
        ja set_gameover
        
        fld dword ptr [birdX]
        fadd dword ptr [birdSize]
        fcomp dword ptr [pipeX]
        fstsw ax
        sahf
        jb coll_end
        
        fld dword ptr [pipeX]
        fadd dword ptr [pipeWidth]
        fcomp dword ptr [birdX]
        fstsw ax
        sahf
        jb coll_end 
        
        fld dword ptr [birdY]
        fcomp dword ptr [pipeGapY]
        fstsw ax
        sahf
        jbe set_gameover 
        
        fld dword ptr [birdY]
        fadd dword ptr [birdSize]
        fld dword ptr [pipeGapY]
        fadd dword ptr [pipeGapSize]
        
        fcompp 
        fstsw ax
        sahf
        jbe set_gameover
        
        jmp coll_end
        
    set_gameover:
        mov byte ptr [gameOver], 1
        
    coll_end:
    }
}

LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_KEYDOWN:
            if (wParam == VK_SPACE) {
                if (gameOver) {
                    InitGame();
                } else if (!playing) {
                    playing = true;
                    jumpRequested = true;
                } else {
                    jumpRequested = true;
                }
            }
            break;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProc(hWnd, message, wParam, lParam);
    }
    return 0;
}

// Helper to draw text with shadow
void DrawShadowText(Graphics& g, const std::wstring& text, Font* font, const PointF& pos, Brush* mainBrush, StringFormat* format = nullptr) {
    SolidBrush shadowBrush(Color(200, 0, 0, 0));
    PointF shadowPos(pos.X + 2.0f, pos.Y + 2.0f); // Reduced offset
    if (format) {
        g.DrawString(text.c_str(), -1, font, shadowPos, format, &shadowBrush);
        g.DrawString(text.c_str(), -1, font, pos, format, mainBrush);
    } else {
        g.DrawString(text.c_str(), -1, font, shadowPos, &shadowBrush);
        g.DrawString(text.c_str(), -1, font, pos, mainBrush);
    }
}

// Helper to pre-scale images to avoid slow DrawImage scaling in the game loop
Image* LoadAndResize(const wchar_t* path, int w, int h) {
    Image* orig = new Image(path);
    if (!orig || orig->GetLastStatus() != Ok) {
        delete orig;
        return nullptr;
    }
    Bitmap* bmp = new Bitmap(w, h, PixelFormat32bppARGB);
    Graphics g(bmp);
    // Nearest neighbor preserves hard edges for pixel art!
    g.SetInterpolationMode(InterpolationModeNearestNeighbor);
    g.DrawImage(orig, 0, 0, w, h);
    delete orig;
    return bmp;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken;
    GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);

    WNDCLASSEX wcex = {0};
    wcex.cbSize = sizeof(WNDCLASSEX);
    wcex.style = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc = WndProc;
    wcex.cbClsExtra = 0;
    wcex.cbWndExtra = 0;
    wcex.hInstance = hInstance;
    wcex.hCursor = LoadCursor(NULL, IDC_ARROW);
    wcex.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wcex.lpszClassName = L"FlappyBirdClass";

    RegisterClassEx(&wcex);

    HWND hWnd = CreateWindow(L"FlappyBirdClass", L"Flappy Bird (Win32 Assembly)", 
                             WS_OVERLAPPEDWINDOW ^ WS_THICKFRAME ^ WS_MAXIMIZEBOX, 
                             CW_USEDEFAULT, CW_USEDEFAULT, 800, 600, 
                             NULL, NULL, hInstance, NULL);

    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);
    
    InitGame();

    MSG msg = {0};
    DWORD lastTime = GetTickCount();
    
    // Load Images (Assume they are in the same folder as the exe)
    // Pre-scale images to avoid severe performance issues from large file sizes
    Image* imgBg = LoadAndResize(L"bg.png", 800, 600);
    Image* imgBird = LoadAndResize(L"bird.png", 56, 40); // Increased Bird Size
    
    HDC hdc = GetDC(hWnd);
    HDC memDC = CreateCompatibleDC(hdc);
    HBITMAP memBitmap = CreateCompatibleBitmap(hdc, 800, 600);
    SelectObject(memDC, memBitmap);
    Graphics graphics(memDC);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetInterpolationMode(InterpolationModeNearestNeighbor); // Good for pixel art rendering

    while (msg.message != WM_QUIT) {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        } else {
            DWORD currentTime = GetTickCount();
            if (currentTime - lastTime > 16) { // ~60 FPS
                lastTime = currentTime;

                if (playing && !gameOver) {
                    UpdatePhysicsAsm();

                    for (auto& p : pipes) {
                        p.x -= 3.5f; // Smooth motion speed
                        if (!p.scored && p.x + 60.0f < birdX) {
                            score++;
                            if (score > highScore) highScore = score;
                            p.scored = true;
                        }
                        CheckCollisionAsm(p.x, p.gapY, p.gapSize);
                    }
                    if (!pipes.empty() && pipes.front().x < -100.0f) {
                        pipes.erase(pipes.begin());
                    }
                    if (pipes.back().x < 500.0f) {
                        float gap_y = (float)(rand() % 200 + 100);
                        pipes.push_back({800.0f, gap_y, 150.0f, false});
                    }
                }

                // --- RENDERING ---
                graphics.Clear(Color(255, 135, 206, 235)); 

                // Draw Background
                if (imgBg && imgBg->GetLastStatus() == Ok) {
                    graphics.DrawImage(imgBg, 0, 0, 800, 600);
                }
                
                // Draw Pipes with aesthetic GDI+ graphics
                SolidBrush pipeBrush(Color(255, 115, 191, 46)); // Classic retro green
                Pen pipePen(Color(255, 84, 56, 71), 2.0f); // Dark outline
                
                for (const auto& p : pipes) {
                    // Top pipe body
                    graphics.FillRectangle(&pipeBrush, p.x, 0.0f, 60.0f, p.gapY - 24.0f);
                    graphics.DrawRectangle(&pipePen, p.x, 0.0f, 60.0f, p.gapY - 24.0f);
                    // Top pipe cap
                    graphics.FillRectangle(&pipeBrush, p.x - 4.0f, p.gapY - 24.0f, 68.0f, 24.0f);
                    graphics.DrawRectangle(&pipePen, p.x - 4.0f, p.gapY - 24.0f, 68.0f, 24.0f);
                    
                    // Bottom pipe cap
                    graphics.FillRectangle(&pipeBrush, p.x - 4.0f, p.gapY + p.gapSize, 68.0f, 24.0f);
                    graphics.DrawRectangle(&pipePen, p.x - 4.0f, p.gapY + p.gapSize, 68.0f, 24.0f);
                    // Bottom pipe body
                    graphics.FillRectangle(&pipeBrush, p.x, p.gapY + p.gapSize + 24.0f, 60.0f, 600.0f);
                    graphics.DrawRectangle(&pipePen, p.x, p.gapY + p.gapSize + 24.0f, 60.0f, 600.0f);
                }

                // Draw Bird
                float birdWidth = 56.0f; // Increased
                float birdHeight = 40.0f; // Increased
                
                GraphicsState state = graphics.Save();
                graphics.TranslateTransform(birdX + birdWidth / 2, birdY + birdHeight / 2);
                
                // Rotation logic: Tilt up when going up, straight normally/down
                float angle = 0.0f;
                if (playing) {
                    if (birdVelocity < 0.0f) {
                        angle = -20.0f; // Tilt up
                    } else {
                        angle = 0.0f;   // Go straight normally
                    }
                }
                graphics.RotateTransform(angle);
                
                if (imgBird && imgBird->GetLastStatus() == Ok) {
                    graphics.DrawImage(imgBird, -birdWidth / 2, -birdHeight / 2, birdWidth, birdHeight);
                } else {
                    SolidBrush yellowBrush(Color(255, 255, 215, 0));
                    graphics.FillEllipse(&yellowBrush, -birdWidth / 2, -birdHeight / 2, birdWidth, birdHeight);
                }
                graphics.Restore(state);

                // UI
                FontFamily fontFamily(L"Impact");
                Font font(&fontFamily, 32, FontStyleRegular, UnitPixel);
                Font fontSmall(&fontFamily, 24, FontStyleRegular, UnitPixel);
                SolidBrush whiteBrush(Color(255, 255, 255, 255));
                SolidBrush highlightBrush(Color(255, 255, 215, 0)); // Gold for High Score
                
                std::wstring scoreText = L"Score: " + std::to_wstring(score);
                std::wstring highScoreText = L"High Score: " + std::to_wstring(highScore);
                
                DrawShadowText(graphics, scoreText, &font, PointF(20.0f, 20.0f), &whiteBrush);
                DrawShadowText(graphics, highScoreText, &fontSmall, PointF(20.0f, 60.0f), &highlightBrush);

                StringFormat centerFormat;
                centerFormat.SetAlignment(StringAlignmentCenter);
                centerFormat.SetLineAlignment(StringAlignmentCenter);

                if (gameOver) {
                    // Darken background
                    SolidBrush overlayBrush(Color(150, 0, 0, 0));
                    graphics.FillRectangle(&overlayBrush, 0, 0, 800, 600);
                    
                    // Draw nice panel
                    SolidBrush panelBrush(Color(220, 222, 184, 135)); 
                    Pen panelPen(Color(255, 139, 69, 19), 6.0f);
                    graphics.FillRectangle(&panelBrush, 220, 150, 360, 240);
                    graphics.DrawRectangle(&panelPen, 220, 150, 360, 240);
                    
                    Font fontBig(&fontFamily, 56, FontStyleRegular, UnitPixel);
                    SolidBrush redBrush(Color(255, 230, 40, 40));
                    
                    DrawShadowText(graphics, L"GAME OVER", &fontBig, PointF(400.0f, 190.0f), &redBrush, &centerFormat);
                    
                    std::wstring finalScoreText = L"Score: " + std::to_wstring(score);
                    DrawShadowText(graphics, finalScoreText, &font, PointF(400.0f, 260.0f), &whiteBrush, &centerFormat);
                    DrawShadowText(graphics, highScoreText, &font, PointF(400.0f, 305.0f), &highlightBrush, &centerFormat);
                    
                    DrawShadowText(graphics, L"Press SPACE to Restart", &fontSmall, PointF(400.0f, 360.0f), &whiteBrush, &centerFormat);
                } else if (!playing) {
                    // Darken background slightly
                    SolidBrush overlayBrush(Color(100, 0, 0, 0));
                    graphics.FillRectangle(&overlayBrush, 0, 0, 800, 600);
                    
                    Font fontBig(&fontFamily, 72, FontStyleRegular, UnitPixel);
                    SolidBrush titleBrush(Color(255, 255, 165, 0));
                    DrawShadowText(graphics, L"FLAPPY BIRD", &fontBig, PointF(400.0f, 200.0f), &titleBrush, &centerFormat);
                    DrawShadowText(graphics, L"Press SPACE to Start", &font, PointF(400.0f, 280.0f), &whiteBrush, &centerFormat);
                }

                BitBlt(hdc, 0, 0, 800, 600, memDC, 0, 0, SRCCOPY);
            }
        }
    }

    if(imgBg) delete imgBg;
    if(imgBird) delete imgBird;

    DeleteObject(memBitmap);
    DeleteDC(memDC);
    ReleaseDC(hWnd, hdc);
    GdiplusShutdown(gdiplusToken);

    return (int)msg.wParam;
}
