{*******************************************************************************
  SkiaCatsLife (2.5D Isometric Apartment Prototype)
********************************************************************************
  A high-performance, thread-safe 2.5D isometric engine built on Skia4Delphi.

  Features:
  - Center-based coordinate system (inspired by Flare RPG / OpenTTD)
  - Procedural 3D iso-box rendering with perfect grid alignment
  - Click-to-move cat with smooth Z-axis interpolation (jumping)
  - X-ray vision: Objects become transparent when the cat is behind them
  - Destructible physics items (glasses fall and shatter into particles)
  - Chaseable mouse with simple wandering AI

  Author:  Lara Miriam Tamy Reschke
  License: MIT
*******************************************************************************}

unit SkiaCatsLife;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math,
  System.Generics.Collections, System.Generics.Defaults, System.UITypes,
  System.SyncObjs, FMX.Types, FMX.Controls, FMX.Forms, FMX.Skia, System.Skia;

const
  // Isometric tile dimensions. A 2:1 ratio (width:height) is standard for true isometric projection.
  TILE_W = 64;
  TILE_H = 32;

  MAP_COLS = 14;
  MAP_ROWS = 14;

  // Maximum height difference the cat can step up without jumping mechanics.
  MAX_STEP_HEIGHT = 40;

type
  TTileType = (ttWood, ttCarpet, ttKitchen, ttEmpty);
  TObjKind = (okCat, okSofa, okTable, okPlant, okGlass, okWardrobe, okTV, okBed, okCounter, okMouse);

  {
    TGameObject
    Represents any entity in the world (furniture, cat, mouse, items).
    Uses a center-based grid coordinate system (GridX, GridY) rather than top-left,
    which makes rotations and placements mathematically much simpler.
  }
  TGameObject = class
  public
    GridX: Single;       // Exact center X on the grid (can be fractional)
    GridY: Single;       // Exact center Y on the grid
    SizeX: Integer;      // Tile footprint width
    SizeY: Integer;      // Tile footprint depth
    Z: Single;           // Current vertical position (height above ground)
    TargetZ: Single;     // Desired vertical position (used for smooth interpolation)
    Height: Single;      // Physical height of the object's collision/render box
    RenderX: Single;     // Calculated screen X coordinate (before camera offset)
    RenderY: Single;     // Calculated screen Y coordinate (before camera offset)
    Kind: TObjKind;      // Determines rendering and behavior logic
    Solid: Boolean;      // If true, blocks movement
    CanStandOn: Boolean; // If true, cat can walk on top of it (uses Height)
    IsFalling: Boolean;  // Physics flag for falling objects
    IsShattered: Boolean;// Flag to stop rendering/processing destroyed objects
    VelX, VelY, VelZ: Single; // Velocity vectors for physics calculations
    procedure CalculateRenderPos;
  end;

  {
    TParticle
    Simple record structure for particle effects (e.g., shattering glass).
    Using records instead of classes for particles drastically reduces memory
    allocation overhead during rapid spawning/destruction.
  }
  TParticle = record
    Pos: TPointF;
    Vel: TPointF;
    Life: Single;
    Color: TAlphaColor;
    Size: Single;
  end;

  {
    TSkiCatIsoGame
    The main game control. Handles rendering, physics, input, and threading.
    Inherits from TSkCustomControl to utilize hardware-accelerated Skia drawing.
  }
  TSkiCatIsoGame = class(TSkCustomControl)
  private
    FThread: TThread;
    FActive: Boolean;
    FLock: TCriticalSection; // Ensures thread-safe access to input states (FKeys)
    FKeys: set of Byte;      // Tracks currently pressed keys

    FMap: array[0..MAP_COLS-1, 0..MAP_ROWS-1] of TTileType;
    FObjects: TObjectList<TGameObject>;
    FParticles: TList<TParticle>;

    FPlayer: TGameObject;
    FMouse: TGameObject;

    // Pathfinding/Movement targets for click-to-move
    FTargetX: Single;
    FTargetY: Single;
    FHasTarget: Boolean;

    // Animation states
    FAnimPhase: Single;
    FIsMoving: Boolean;

    // Camera position (follows player)
    FCameraX: Single;
    FCameraY: Single;

    procedure GenerateWorld;
    function CanWalk(X, Y: Single; out ObjZ: Single): Boolean;
    function GetObjAlpha(Obj: TGameObject): Byte;
    procedure DoPhysicsUpdate(DeltaSec: Double);
    procedure SafeInvalidate;
    procedure StartThread;
    procedure StopThread;

    procedure SpawnParticles(X, Y: Single; Color: TAlphaColor);

    procedure DrawTile(const ACanvas: ISkCanvas; Col, Row: Integer; TileType: TTileType; const OffsetX, OffsetY: Single);
    procedure DrawIsoBox(const ACanvas: ISkCanvas; Obj: TGameObject; BoxHeight: Single; TopColor, LeftColor, RightColor: TAlphaColor; const OffsetX, OffsetY: Single);

    procedure DrawObject(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
    procedure DrawShadow(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);

    procedure DrawCat(const ACanvas: ISkCanvas; X, Y: Single; IsMoving: Boolean);
    procedure DrawMouse(const ACanvas: ISkCanvas; X, Y: Single);
    procedure DrawPlant(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
    procedure DrawGlass(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
    procedure DrawParticles(const ACanvas: ISkCanvas; const OffsetX, OffsetY: Single);
  protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  end;

implementation

{ TGameObject }
procedure TGameObject.CalculateRenderPos;
begin
  // Standard Isometric Projection formula.
  // Screen X is derived from the difference of Grid X and Y.
  // Screen Y is derived from the sum of Grid X and Y.
  // Because GridX/GridY represent the exact center, RenderX/RenderY will be the
  // screen-coordinate center of the tile footprint.
  RenderX := (GridX - GridY) * (TILE_W / 2);
  RenderY := (GridX + GridY) * (TILE_H / 2);
end;

{ TSkiCatIsoGame }
procedure TSkiCatIsoGame.GenerateWorld;
var
  X, Y: Integer;
  Obj: TGameObject;
begin
  // 1. Initialize Apartment Layout
  // Create distinct rooms based on grid quadrants. Borders are empty (void).
  for Y := 0 to MAP_ROWS - 1 do
    for X := 0 to MAP_COLS - 1 do
    begin
      if (X = 0) or (Y = 0) or (X = MAP_COLS - 1) or (Y = MAP_ROWS - 1) then
        FMap[X, Y] := ttEmpty
      else if (X <= 6) and (Y <= 6) then
        FMap[X, Y] := ttWood
      else if (X >= 7) and (Y <= 6) then
        FMap[X, Y] := ttKitchen
      else if (X <= 6) and (Y >= 7) then
        FMap[X, Y] := ttCarpet
      else
        FMap[X, Y] := ttWood;
    end;

  FObjects.Clear;
  FParticles.Clear;

  // 2. Place Furniture
  // Note: Coordinates are exact centers. SizeX/SizeY determine how many tiles are occupied.

  // Sofa (2x1 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 2.5; Obj.GridY := 2.0; Obj.SizeX := 2; Obj.SizeY := 1;
  Obj.Kind := okSofa; Obj.Solid := True; Obj.CanStandOn := True; Obj.Height := 20;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Table (2x1 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 4.5; Obj.GridY := 4.0; Obj.SizeX := 2; Obj.SizeY := 1;
  Obj.Kind := okTable; Obj.Solid := True; Obj.CanStandOn := True; Obj.Height := 35;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Glasses on Table (Elevated Z)
  Obj := TGameObject.Create;
  Obj.GridX := 4.2; Obj.GridY := 4.2; Obj.SizeX := 1; Obj.SizeY := 1;
  Obj.Z := 35; Obj.Kind := okGlass; Obj.Solid := False; Obj.CanStandOn := False;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  Obj := TGameObject.Create;
  Obj.GridX := 4.8; Obj.GridY := 4.2; Obj.SizeX := 1; Obj.SizeY := 1;
  Obj.Z := 35; Obj.Kind := okGlass; Obj.Solid := False; Obj.CanStandOn := False;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  Obj := TGameObject.Create;
  Obj.GridX := 5.4; Obj.GridY := 4.2; Obj.SizeX := 1; Obj.SizeY := 1;
  Obj.Z := 35; Obj.Kind := okGlass; Obj.Solid := False; Obj.CanStandOn := False;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // TV (2x1 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 5.5; Obj.GridY := 1.0; Obj.SizeX := 2; Obj.SizeY := 1;
  Obj.Kind := okTV; Obj.Solid := True; Obj.CanStandOn := False; Obj.Height := 40;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Plant (1x1 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 1.0; Obj.GridY := 5.0; Obj.SizeX := 1; Obj.SizeY := 1;
  Obj.Kind := okPlant; Obj.Solid := True; Obj.CanStandOn := False; Obj.Height := 0;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Bed (2x3 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 2.5; Obj.GridY := 10.0; Obj.SizeX := 2; Obj.SizeY := 3;
  Obj.Kind := okBed; Obj.Solid := True; Obj.CanStandOn := True; Obj.Height := 20;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Wardrobe (1x2 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 5.0; Obj.GridY := 8.5; Obj.SizeX := 1; Obj.SizeY := 2;
  Obj.Kind := okWardrobe; Obj.Solid := True; Obj.CanStandOn := False; Obj.Height := 90;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Kitchen Counter (4x1 footprint)
  Obj := TGameObject.Create;
  Obj.GridX := 10.5; Obj.GridY := 1.0; Obj.SizeX := 4; Obj.SizeY := 1;
  Obj.Kind := okCounter; Obj.Solid := True; Obj.CanStandOn := True; Obj.Height := 40;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Glasses on Counter
  Obj := TGameObject.Create;
  Obj.GridX := 9.5; Obj.GridY := 1.2; Obj.SizeX := 1; Obj.SizeY := 1;
  Obj.Z := 40; Obj.Kind := okGlass; Obj.Solid := False; Obj.CanStandOn := False;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  Obj := TGameObject.Create;
  Obj.GridX := 11.5; Obj.GridY := 1.2; Obj.SizeX := 1; Obj.SizeY := 1;
  Obj.Z := 40; Obj.Kind := okGlass; Obj.Solid := False; Obj.CanStandOn := False;
  Obj.CalculateRenderPos; FObjects.Add(Obj);

  // Player (Cat)
  FPlayer.GridX := 3.0;
  FPlayer.GridY := 3.0;
  FPlayer.SizeX := 1; FPlayer.SizeY := 1;
  FPlayer.Z := 0;
  FPlayer.Kind := okCat;
  FPlayer.CalculateRenderPos;
  FObjects.Add(FPlayer);

  // Mouse (NPC)
  FMouse := TGameObject.Create;
  FMouse.GridX := 5.0;
  FMouse.GridY := 5.0;
  FMouse.SizeX := 1; FMouse.SizeY := 1;
  FMouse.Z := 0;
  FMouse.Kind := okMouse;
  FMouse.CalculateRenderPos;
  FObjects.Add(FMouse);
end;

function TSkiCatIsoGame.GetObjAlpha(Obj: TGameObject): Byte;
var
  CatDepth, ObjDepth: Single;
  CatDiff, ObjDiff: Single;
begin
  // Characters and dynamic items should never become transparent themselves.
  if (Obj.Kind = okCat) or (Obj.Kind = okMouse) or (Obj.Kind = okGlass) then
    Exit(255);

  // X-Ray Vision Logic:
  // If the cat is standing on top of the object (Z >= Height), the object must remain fully opaque.
  // This prevents the visual glitch where the cat sinks through the back edge of the block.
  if FPlayer.Z >= Obj.Height - 1 then
    Exit(255);

  // Calculate isometric "depth" (distance from camera). We add Z to the sum so that
  // higher objects are considered "closer" to the camera.
  CatDepth := (FPlayer.GridX + FPlayer.GridY) + (FPlayer.Z / TILE_H);
  ObjDepth := (Obj.GridX + Obj.GridY) + (Obj.Z / TILE_H);

  // If the object is further back than the cat...
  if (ObjDepth > CatDepth) then
  begin
    // ...we check their relative screen-X positions.
    // If they align horizontally (diff < 2.0), the object is obstructing the view.
    CatDiff := FPlayer.GridX - FPlayer.GridY;
    ObjDiff := Obj.GridX - Obj.GridY;

    if Abs(CatDiff - ObjDiff) < 2.0 then
      Exit(120); // Make it semi-transparent so we can see the cat behind it!
  end;

  Result := 255; // Default: fully opaque
end;

function TSkiCatIsoGame.CanWalk(X, Y: Single; out ObjZ: Single): Boolean;
var
  TileX, TileY, MinTX, MaxTX, MinTY, MaxTY: Integer;
  Obj: TGameObject;
  CatSum: Single; // Unused, but kept for potential future logic
begin
  Result := False;
  ObjZ := 0;

  // Snap coordinates to tile grid for boundary checks
  TileX := Trunc(X + 0.5);
  TileY := Trunc(Y + 0.5);

  // Boundary check: prevent walking off the map edges
  if (TileX < 1) or (TileX > MAP_COLS - 2) or (TileY < 1) or (TileY > MAP_ROWS - 2) then
    Exit;

  // Check for void tiles
  if FMap[TileX, TileY] = ttEmpty then
    Exit;

  // Check collision against all solid objects
  for Obj in FObjects do
  begin
    if Obj.Solid then
    begin
      // Calculate the bounding box of the object in grid space
      MinTX := Trunc(Obj.GridX - (Obj.SizeX / 2) + 0.5);
      MaxTX := Trunc(Obj.GridX + (Obj.SizeX / 2) - 0.5);
      MinTY := Trunc(Obj.GridY - (Obj.SizeY / 2) + 0.5);
      MaxTY := Trunc(Obj.GridY + (Obj.SizeY / 2) - 0.5);

      // If the target tile overlaps with an object's footprint
      if (TileX >= MinTX) and (TileX <= MaxTX) and
         (TileY >= MinTY) and (TileY <= MaxTY) then
      begin
        // Case 1: The object is walkable (like a table) and we can step up to it
        if Obj.CanStandOn and ((Obj.Height - FPlayer.Z) <= MAX_STEP_HEIGHT) then
        begin
          ObjZ := Obj.Height;
          Result := True;
        end
        else
        begin
          // Case 2: We are hovering above the object (Z > Height).
          // We allow walking over the edge so the player doesn't get stuck
          // when walking off a platform.
          if FPlayer.Z >= Obj.Height - 5 then
          begin
            ObjZ := Obj.Height;
            Result := True;
          end
          else
            Exit(False); // Blocked by a wall/furniture that is too high
        end;
      end;
    end;
  end;

  Result := True;
end;


procedure TSkiCatIsoGame.SpawnParticles(X, Y: Single; Color: TAlphaColor);
var
  I: Integer; P: TParticle;
begin
  // Spawns 16 particles with random outward velocities to simulate an impact/shatter.
  for I := 0 to 15 do
  begin
    P.Pos := PointF(X, Y);
    // Velocity: random X/Y spread, with an initial upward boost (-100 on Y axis)
    P.Vel := PointF((Random - 0.5) * 300, (Random - 0.5) * 300 - 100);
    P.Life := 1.0; P.Color := Color; P.Size := 3 + Random * 4;
    FParticles.Add(P);
  end;
end;

procedure TSkiCatIsoGame.DoPhysicsUpdate(DeltaSec: Double);
var
  Left, Right, Up, Down: Boolean;
  Speed, NewX, NewY, ObjZ: Single;
  IsMoving: Boolean;
  Obj: TGameObject;
  DirX, DirY, Len: Single;
  I: Integer; P: TParticle;
begin
  if not FActive then Exit;

  // --- 1. Particle Physics ---
  // Update position, apply gravity, and decay lifespan.
  for I := FParticles.Count - 1 downto 0 do
  begin
    P := FParticles[I];
    P.Pos := P.Pos + TPointF.Create(P.Vel.X * DeltaSec, P.Vel.Y * DeltaSec);
    P.Vel.Y := P.Vel.Y + 600 * DeltaSec; // Gravity
    P.Life := P.Life - DeltaSec * 1.5;
    if P.Life <= 0 then FParticles.Delete(I) else FParticles[I] := P;
  end;

  // --- 2. Falling Object Physics (Glasses) ---
  for Obj in FObjects do
  begin
    if (Obj.Kind = okGlass) and Obj.IsFalling and not Obj.IsShattered then
    begin
      Obj.GridX := Obj.GridX + Obj.VelX * DeltaSec;
      Obj.GridY := Obj.GridY + Obj.VelY * DeltaSec;
      Obj.Z := Obj.Z + Obj.VelZ * DeltaSec;
      Obj.VelZ := Obj.VelZ - 500 * DeltaSec; // Gravity
      Obj.CalculateRenderPos;

      // Impact detection
      if Obj.Z <= 0 then
      begin
        Obj.Z := 0;
        Obj.IsShattered := True;
        SpawnParticles(Obj.RenderX, Obj.RenderY, $FF00FFFF);
      end;
    end;
  end;

  // --- 3. Player Input & Movement ---
  // Safely read keyboard input from the main thread
  FLock.Acquire;
  try
    Left := (Byte(vkLeft) in FKeys) or (Byte(Ord('A')) in FKeys);
    Right := (Byte(vkRight) in FKeys) or (Byte(Ord('D')) in FKeys);
    Up := (Byte(vkUp) in FKeys) or (Byte(Ord('W')) in FKeys);
    Down := (Byte(vkDown) in FKeys) or (Byte(Ord('S')) in FKeys);
  finally
    FLock.Release;
  end;

  Speed := 4.0 * DeltaSec;
  IsMoving := False;
  NewX := FPlayer.GridX;
  NewY := FPlayer.GridY;

  // If manual keys are pressed, override click-to-move target
  if Left or Right or Up or Down then FHasTarget := False;

  if Left then begin NewX := NewX - Speed; IsMoving := True; end;
  if Right then begin NewX := NewX + Speed; IsMoving := True; end;
  if Up then begin NewY := NewY - Speed; IsMoving := True; end;
  if Down then begin NewY := NewY + Speed; IsMoving := True; end;

  // Click-to-move logic (only if no keys are pressed)
  if FHasTarget and not IsMoving then
  begin
    DirX := FTargetX - FPlayer.GridX;
    DirY := FTargetY - FPlayer.GridY;
    Len := Hypot(DirX, DirY);
    if Len > 0.1 then
    begin
      // Normalize direction and apply speed
      NewX := FPlayer.GridX + (DirX / Len) * Speed;
      NewY := FPlayer.GridY + (DirY / Len) * Speed;
      IsMoving := True;
    end
    else
      FHasTarget := False; // Reached target
  end;

  FPlayer.TargetZ := FPlayer.Z;

  // Axis-Separated Collision Detection:
  // We check X and Y movement independently. This allows the player to "slide"
  // along walls instead of getting stuck completely when moving diagonally.

  // Check X axis
  if CanWalk(NewX, FPlayer.GridY, ObjZ) then
  begin
    FPlayer.GridX := NewX;
    FPlayer.TargetZ := ObjZ;
  end;

  // Check Y axis (using the newly accepted X value!)
  if CanWalk(FPlayer.GridX, NewY, ObjZ) then
  begin
    FPlayer.GridY := NewY;
    FPlayer.TargetZ := ObjZ;
  end;

  // Final Z resolution. We evaluate the final position to ensure TargetZ is correct.
  // This prevents TargetZ from dropping to 0 erroneously during diagonal wall slides.
  if CanWalk(FPlayer.GridX, FPlayer.GridY, ObjZ) then
    FPlayer.TargetZ := ObjZ
  else
    FPlayer.TargetZ := 0;

  // Smooth Z interpolation (Jump up / Fall down)
  if FPlayer.Z < FPlayer.TargetZ then
    FPlayer.Z := FPlayer.Z + Min(150 * DeltaSec, FPlayer.TargetZ - FPlayer.Z)
  else if FPlayer.Z > FPlayer.TargetZ then
    FPlayer.Z := FPlayer.Z - Min(200 * DeltaSec, FPlayer.Z - FPlayer.TargetZ);

  // Update animation states
  FIsMoving := IsMoving;
  if IsMoving then FAnimPhase := FAnimPhase + DeltaSec * 10 else FAnimPhase := 0;
  FPlayer.CalculateRenderPos;

  // --- 4. Interactions ---
  // Check if cat bumps into a glass to knock it off
  for Obj in FObjects do
  begin
    if (Obj.Kind = okGlass) and not Obj.IsFalling and not Obj.IsShattered then
    begin
      if (Abs(FPlayer.GridX - Obj.GridX) < 0.5) and (Abs(FPlayer.GridY - Obj.GridY) < 0.5) and (Abs(FPlayer.Z - Obj.Z) < 10) then
      begin
        Obj.IsFalling := True;
        // Push glass away from the cat's movement direction
        Obj.VelX := (Obj.GridX - FPlayer.GridX) * 3;
        Obj.VelY := (Obj.GridY - FPlayer.GridY) * 3;
        Obj.VelZ := 150; // Initial hop upwards
      end;
    end;
  end;

  // --- 5. Mouse AI ---
  // 5% chance per frame to wander randomly
  if Random(100) < 5 then
  begin
    FMouse.GridX := EnsureRange(FMouse.GridX + (Random - 0.5) * 2, 1.5, MAP_COLS - 2.5);
    FMouse.GridY := EnsureRange(FMouse.GridY + (Random - 0.5) * 2, 1.5, MAP_ROWS - 2.5);
    FMouse.CalculateRenderPos;
  end;

  // If cat catches the mouse, teleport mouse to a new random location
  if (Abs(FPlayer.GridX - FMouse.GridX) < 0.5) and (Abs(FPlayer.GridY - FMouse.GridY) < 0.5) then
  begin
    FMouse.GridX := Random(MAP_COLS - 3) + 1.5;
    FMouse.GridY := Random(MAP_ROWS - 3) + 1.5;
    FMouse.CalculateRenderPos;
  end;

  // --- 6. Camera Update ---
  // Camera rigidly follows the player's render position
  FCameraX := FPlayer.RenderX;
  FCameraY := FPlayer.RenderY;
end;

procedure TSkiCatIsoGame.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  ScreenX, ScreenY, GridX, GridY, ObjZ: Single;
  IntX, IntY: Integer;
begin
  if Button = TMouseButton.mbLeft then
  begin
    // Convert Screen coordinates to World coordinates (reverse camera offset)
    ScreenX := X + (FCameraX - Width / 2);
    ScreenY := Y + (FCameraY - Height / 2);

    // Reverse Isometric Projection formula to find grid coordinates
    GridX := (ScreenX / (TILE_W / 2) + ScreenY / (TILE_H / 2)) / 2;
    GridY := (ScreenY / (TILE_H / 2) - ScreenX / (TILE_W / 2)) / 2;

    // Attempt to path to the exact clicked tile
    if CanWalk(GridX, GridY, ObjZ) then
    begin
      FTargetX := GridX;
      FTargetY := GridY;
      FHasTarget := True;
    end
    else
    begin
      // Fallback: If the exact spot is blocked (e.g. clicked inside a wall),
      // try the tile directly "below" it (south) to make clicking easier for the user.
      IntX := Trunc(GridX + 0.5);
      IntY := Trunc(GridY + 0.5) + 1;
      if CanWalk(IntX, IntY, ObjZ) then
      begin
        FTargetX := IntX;
        FTargetY := IntY;
        FHasTarget := True;
      end;
    end;
  end;
  inherited;
end;

procedure TSkiCatIsoGame.DrawTile(const ACanvas: ISkCanvas; Col, Row: Integer; TileType: TTileType; const OffsetX, OffsetY: Single);
var
  CX, CY: Single;
  PB: ISkPathBuilder;
  Paint: ISkPaint;
begin
  // Calculate the center point of the tile in screen space
  CX := (Col - Row) * (TILE_W / 2) - OffsetX;
  CY := (Col + Row) * (TILE_H / 2) - OffsetY;

  // Offset Y upwards by half a tile height.
  // Because our projection formula places the center of the tile at the grid intersection,
  // we need to shift up so the top vertex of the diamond aligns correctly.
  CY := CY - (TILE_H / 2);

  // Draw the diamond shape (Rhombus)
  PB := TSkPathBuilder.Create;
  PB.MoveTo(CX, CY);                       // Top Vertex
  PB.LineTo(CX + TILE_W / 2, CY + TILE_H / 2); // Right Vertex
  PB.LineTo(CX, CY + TILE_H);              // Bottom Vertex
  PB.LineTo(CX - TILE_W / 2, CY + TILE_H / 2); // Left Vertex
  PB.Close;

  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  // Apply floor colors based on room type
  case TileType of
    ttWood:    Paint.Color := $FFD2B48C;
    ttCarpet:  Paint.Color := $FFB22222;
    ttKitchen: Paint.Color := $FFE0E0E0;
    ttEmpty:   Paint.Color := $FF1a1a1a; // Void / background
  end;
  ACanvas.DrawPath(PB.Snapshot, Paint);

  // Draw subtle grid lines for non-empty tiles to help visual depth perception
  if TileType <> ttEmpty then
  begin
    Paint.Style := TSkPaintStyle.Stroke;
    Paint.StrokeWidth := 1; Paint.Color := $FF000000; Paint.Alpha := 30;
    ACanvas.DrawPath(PB.Snapshot, Paint);
  end;
end;


procedure TSkiCatIsoGame.DrawIsoBox(const ACanvas: ISkCanvas; Obj: TGameObject; BoxHeight: Single; TopColor, LeftColor, RightColor: TAlphaColor; const OffsetX, OffsetY: Single);
var
  MinX, MaxX, MinY, MaxY: Single;
  A: Byte;
  P1, P2, P3, P4: TPointF;
  PB: ISkPathBuilder;
  Paint: ISkPaint;
  TC, LC, RC: TAlphaColor;
begin
  // Get X-Ray transparency alpha value for this object
  A := GetObjAlpha(Obj);
  TC := TopColor; TAlphaColorRec(TC).A := A;
  LC := LeftColor; TAlphaColorRec(LC).A := A;
  RC := RightColor; TAlphaColorRec(RC).A := A;

  // Calculate the 4 corners of the tile footprint the box sits on
  MinX := Obj.GridX - (Obj.SizeX / 2);
  MaxX := Obj.GridX + (Obj.SizeX / 2);
  MinY := Obj.GridY - (Obj.SizeY / 2);
  MaxY := Obj.GridY + (Obj.SizeY / 2);

  // Convert corners to screen space. Note: We don't subtract TILE_H/2 here because
  // we want the base of the box to sit on the grid line, and the box extends UPWARDS.
  P1 := PointF((MinX - MinY) * (TILE_W / 2) - OffsetX, (MinX + MinY) * (TILE_H / 2) - OffsetY); // Top-Left Corner
  P2 := PointF((MaxX - MinY) * (TILE_W / 2) - OffsetX, (MaxX + MinY) * (TILE_H / 2) - OffsetY); // Top-Right Corner
  P3 := PointF((MaxX - MaxY) * (TILE_W / 2) - OffsetX, (MaxX + MaxY) * (TILE_H / 2) - OffsetY); // Bottom-Right Corner
  P4 := PointF((MinX - MaxY) * (TILE_W / 2) - OffsetX, (MinX + MaxY) * (TILE_H / 2) - OffsetY); // Bottom-Left Corner

  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  // Draw Right Face (darker shade)
  Paint.Color := RC;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(P2.X, P2.Y);
  PB.LineTo(P3.X, P3.Y);
  PB.LineTo(P3.X, P3.Y - BoxHeight); // Move up by BoxHeight
  PB.LineTo(P2.X, P2.Y - BoxHeight);
  PB.Close;
  ACanvas.DrawPath(PB.Snapshot, Paint);

  // Draw Left Face (medium shade)
  Paint.Color := LC;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(P4.X, P4.Y);
  PB.LineTo(P3.X, P3.Y);
  PB.LineTo(P3.X, P3.Y - BoxHeight);
  PB.LineTo(P4.X, P4.Y - BoxHeight);
  PB.Close;
  ACanvas.DrawPath(PB.Snapshot, Paint);

  // Draw Top Face (brightest shade)
  Paint.Color := TC;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(P1.X, P1.Y - BoxHeight);
  PB.LineTo(P2.X, P2.Y - BoxHeight);
  PB.LineTo(P3.X, P3.Y - BoxHeight);
  PB.LineTo(P4.X, P4.Y - BoxHeight);
  PB.Close;
  ACanvas.DrawPath(PB.Snapshot, Paint);
end;

procedure TSkiCatIsoGame.DrawShadow(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
var
  ScreenX, ScreenY: Single; Paint: ISkPaint;
begin
  // Draw a dynamic drop shadow that shrinks and fades the higher the object is (Z > 0)
  if Obj.Z > 0 then
  begin
    ScreenX := Obj.RenderX - OffsetX;
    ScreenY := Obj.RenderY - OffsetY;
    Paint := TSkPaint.Create(TSkPaintStyle.Fill);
    Paint.AntiAlias := True;
    Paint.Color := $FF000000;
    // Fade alpha based on height. 100 is an arbitrary max height for shadow scaling.
    Paint.Alpha := Round(80 * (1 - (Obj.Z / 100)));
    ACanvas.DrawOval(TRectF.Create(ScreenX-15, ScreenY-7, ScreenX+15, ScreenY+7), Paint);
  end;
end;

procedure TSkiCatIsoGame.DrawCat(const ACanvas: ISkCanvas; X, Y: Single; IsMoving: Boolean);
var
  Paint, GlowPaint: ISkPaint;
  BodyRect, HeadRect: TRectF;
  TailWag, RunPhase, Breathe: Single;
  PB: ISkPathBuilder;
begin
  // Setup base paints
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.Color := $FF2a2a2a; // Dark fur

  // Neon glow effect
  GlowPaint := TSkPaint.Create(Paint);
  GlowPaint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 3.0);
  GlowPaint.Color := $FF00FFFF;

  var Scale: Single := 0.8;
  var CX: Single := X;
  // Shift the cat downwards slightly so its visually centered on the tile (paws on ground)
  var CY: Single := Y + 8;

  // Animation math
  RunPhase := FAnimPhase * 10;
  TailWag := Sin(FAnimPhase * 6) * 4.0;
  if not IsMoving then Breathe := Sin(FAnimPhase * 2) * 1.0 else Breathe := 0;

  // Body Drawing
  if IsMoving then
    BodyRect := TRectF.Create(CX - 10*Scale, CY - 8*Scale, CX + 10*Scale, CY + 8*Scale)
  else
    // Idle breathing effect expands/contracts the body slightly
    BodyRect := TRectF.Create(CX - 10*Scale, CY - 8*Scale - Breathe, CX + 10*Scale, CY + 8*Scale + Breathe);

  ACanvas.DrawOval(BodyRect, GlowPaint);
  ACanvas.DrawOval(BodyRect, Paint);

  // Legs (only drawn when moving)
  if IsMoving then
  begin
    Paint.Style := TSkPaintStyle.Stroke;
    Paint.StrokeWidth := 3.0 * Scale;
    Paint.StrokeCap := TSkStrokeCap.Round;
    var LegOffset: Single := Sin(RunPhase) * 3.0; // Alternating leg movement
    ACanvas.DrawLine(PointF(BodyRect.Left + 3, BodyRect.Bottom), PointF(BodyRect.Left + 3 + LegOffset, BodyRect.Bottom + 5*Scale), Paint);
    ACanvas.DrawLine(PointF(BodyRect.Left + 7, BodyRect.Bottom), PointF(BodyRect.Left + 7 - LegOffset, BodyRect.Bottom + 5*Scale), Paint);
    ACanvas.DrawLine(PointF(BodyRect.Right - 3, BodyRect.Bottom), PointF(BodyRect.Right - 3 + LegOffset, BodyRect.Bottom + 5*Scale), Paint);
    ACanvas.DrawLine(PointF(BodyRect.Right - 7, BodyRect.Bottom), PointF(BodyRect.Right - 7 - LegOffset, BodyRect.Bottom + 5*Scale), Paint);
    Paint.Style := TSkPaintStyle.Fill;
  end;

  // Head Drawing
  HeadRect := TRectF.Create(CX - 7*Scale, CY - 18*Scale, CX + 7*Scale, CY - 4*Scale);
  ACanvas.DrawOval(HeadRect, GlowPaint);
  ACanvas.DrawOval(HeadRect, Paint);

  // Ears (Triangles)
  PB := TSkPathBuilder.Create;
  PB.MoveTo(HeadRect.Left + 1, HeadRect.Top + 3);
  PB.LineTo(HeadRect.Left + 3, HeadRect.Top - 6);
  PB.LineTo(HeadRect.Left + 7, HeadRect.Top + 3);
  PB.MoveTo(HeadRect.Right - 7, HeadRect.Top + 3);
  PB.LineTo(HeadRect.Right - 3, HeadRect.Top - 6);
  PB.LineTo(HeadRect.Right - 1, HeadRect.Top + 3);
  ACanvas.DrawPath(PB.Snapshot, Paint);

  // Tail (Curved bezier path that wags)
  Paint.Style := TSkPaintStyle.Stroke;
  PB := TSkPathBuilder.Create;
  PB.MoveTo(BodyRect.Right - 4, BodyRect.CenterPoint.Y);
  PB.QuadTo(BodyRect.Right + 2, CY + 4 + TailWag, BodyRect.Right - 2, CY - 6 + TailWag);
  ACanvas.DrawPath(PB.Snapshot, Paint);

  // Eyes (Yellow sclera, black pupils)
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := TAlphaColors.Yellow;
  ACanvas.DrawCircle(PointF(HeadRect.CenterPoint.X - 2, HeadRect.CenterPoint.Y), 1.5*Scale, Paint);
  ACanvas.DrawCircle(PointF(HeadRect.CenterPoint.X + 2, HeadRect.CenterPoint.Y), 1.5*Scale, Paint);
  Paint.Color := TAlphaColors.Black;
  ACanvas.DrawCircle(PointF(HeadRect.CenterPoint.X - 2, HeadRect.CenterPoint.Y), 0.8*Scale, Paint);
  ACanvas.DrawCircle(PointF(HeadRect.CenterPoint.X + 2, HeadRect.CenterPoint.Y), 0.8*Scale, Paint);
end;

procedure TSkiCatIsoGame.DrawMouse(const ACanvas: ISkCanvas; X, Y: Single);
var
  Paint: ISkPaint;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.Color := $FFAAAAAA; // Gray body

  var CX: Single := X;
  var CY: Single := Y + 8; // Match ground offset with Cat

  ACanvas.DrawCircle(PointF(CX, CY - 4), 5, Paint);
  Paint.Color := $FFDDA0DD; // Pink ears
  ACanvas.DrawCircle(PointF(CX-3, CY-8), 2, Paint);
  ACanvas.DrawCircle(PointF(CX+3, CY-8), 2, Paint);
end;


procedure TSkiCatIsoGame.DrawPlant(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
var
  Paint: ISkPaint;
  CX, CY, A: Single;
begin
  // Respect X-Ray transparency
  A := GetObjAlpha(Obj);

  // Draw the pot
  DrawIsoBox(ACanvas, Obj, 20, $FF8B4513, $FF5A2D0C, $FF3E1A06, OffsetX, OffsetY);

  // Draw the foliage above the pot
  CX := Obj.RenderX - OffsetX;
  CY := Obj.RenderY - OffsetY - 20;
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.Alpha := Round(A);

  Paint.Color := $FF228B22;
  ACanvas.DrawCircle(PointF(CX, CY-15), 12, Paint);
  Paint.Color := $FF2E8B57;
  ACanvas.DrawCircle(PointF(CX-8, CY-10), 8, Paint);
  ACanvas.DrawCircle(PointF(CX+8, CY-10), 8, Paint);
end;

procedure TSkiCatIsoGame.DrawGlass(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
var
  Paint: ISkPaint;
  CX, CY, A: Single;
begin
  // Don't draw shattered glasses
  if Obj.IsShattered then Exit;

  CX := Obj.RenderX - OffsetX;
  CY := Obj.RenderY - OffsetY - Obj.Z; // Apply Z height
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  A := GetObjAlpha(Obj);

  // Glass body (semi-transparent blue)
  Paint.Color := $FF88CCFF;
  Paint.Alpha := Round(A * 0.7);
  ACanvas.DrawRect(TRectF.Create(CX-4, CY-15, CX+4, CY), Paint);

  // Glass rim (opaque white)
  Paint.Color := $FFDDDDDD;
  Paint.Alpha := Round(A);
  ACanvas.DrawRect(TRectF.Create(CX-4, CY-15, CX+4, CY-12), Paint);
end;

procedure TSkiCatIsoGame.DrawParticles(const ACanvas: ISkCanvas; const OffsetX, OffsetY: Single);
var
  P: TParticle; Paint: ISkPaint;
begin
  if FParticles.Count = 0 then Exit;
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 3.0);

  // Render each particle, scaling size and alpha based on remaining Life
  for P in FParticles do
  begin
    Paint.Color := P.Color;
    Paint.Alpha := Round(P.Life * 255);
    ACanvas.DrawCircle(P.Pos.X - OffsetX, P.Pos.Y - OffsetY, P.Size * P.Life, Paint);
  end;
end;

procedure TSkiCatIsoGame.DrawObject(const ACanvas: ISkCanvas; Obj: TGameObject; const OffsetX, OffsetY: Single);
var
  ScreenX, ScreenY: Single;
begin
  ScreenX := Obj.RenderX - OffsetX;

  // Important: Furniture has Z=0. We do NOT subtract Obj.Z here by default,
  // otherwise furniture would float. Z is applied manually inside specific entity draws (Cat, Glass).
  ScreenY := Obj.RenderY - OffsetY;

  case Obj.Kind of
    okCat: DrawCat(ACanvas, ScreenX, ScreenY - Obj.Z, FIsMoving); // Apply Z height!
    okMouse: DrawMouse(ACanvas, ScreenX, ScreenY - Obj.Z);
    okSofa: begin
      DrawIsoBox(ACanvas, Obj, 20, $FF8F4565, $FF6B3550, $FF4A2535, OffsetX, OffsetY);
      DrawIsoBox(ACanvas, Obj, 25, $FFB56F8F, $FF9F5575, $FF8F4565, OffsetX, OffsetY);
    end;
    okTable: DrawIsoBox(ACanvas, Obj, 35, $FFA0522D, $FF8B4513, $FF5A2D0C, OffsetX, OffsetY);
    okTV: DrawIsoBox(ACanvas, Obj, 40, $FF222222, $FF111111, $FF000000, OffsetX, OffsetY);
    okBed: begin
      DrawIsoBox(ACanvas, Obj, 20, $FF8B0000, $FF5A0000, $FF3A0000, OffsetX, OffsetY);
      DrawIsoBox(ACanvas, Obj, 30, $FFFFFFFF, $FFDDDDDD, $FFAAAAAA, OffsetX, OffsetY);
    end;
    okWardrobe: DrawIsoBox(ACanvas, Obj, 90, $FF4E342E, $FF3E2723, $FF2D1B16, OffsetX, OffsetY);
    okCounter: DrawIsoBox(ACanvas, Obj, 40, $FFEEEEEE, $FFCCCCCC, $FFAAAAAA, OffsetX, OffsetY);
    okPlant: DrawPlant(ACanvas, Obj, OffsetX, OffsetY);
    okGlass: DrawGlass(ACanvas, Obj, OffsetX, OffsetY);
  end;
end;


procedure TSkiCatIsoGame.Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
var
  X, Y, I: Integer;
  ScreenCenterX, ScreenCenterY, OffsetX, OffsetY: Single;
  DrawList: TList<TGameObject>;
begin
  ACanvas.Clear($FF1a1a1a);

  // Calculate camera offset to center the player on screen
  ScreenCenterX := Width / 2;
  ScreenCenterY := Height / 2;
  OffsetX := FCameraX - ScreenCenterX;
  OffsetY := FCameraY - ScreenCenterY;

  // 1. Draw Floor Tiles
  for Y := 0 to MAP_ROWS - 1 do
    for X := 0 to MAP_COLS - 1 do
      DrawTile(ACanvas, X, Y, FMap[X, Y], OffsetX, OffsetY);

  // 2. Prepare Objects for rendering
  DrawList := TList<TGameObject>.Create;
  try
    // Copy references into a temporary list. We must NOT sort FObjects directly
    // because FObjects owns the objects and altering its order could cause issues
    // elsewhere in the physics loop.
    for I := 0 to FObjects.Count - 1 do
      DrawList.Add(FObjects[I]);

    // Painter's Algorithm: Sort objects by isometric depth.
    // Depth = GridX + GridY + Z. This ensures objects further "back" are drawn first,
    // and objects on top of platforms (Z > 0) are drawn after the platform.
    DrawList.Sort(
      TComparer<TGameObject>.Construct(
        function(const A, B: TGameObject): Integer
        var
          DepthA, DepthB: Single;
        begin
          DepthA := (A.GridX + A.GridY) + (A.Z / TILE_H);
          DepthB := (B.GridX + B.GridY) + (B.Z / TILE_H);

          if DepthA < DepthB then Result := -1
          else if DepthA > DepthB then Result := 1
          else Result := 0;
        end
      )
    );

    // 3. Draw Shadows (Pass 1)
    for I := 0 to DrawList.Count - 1 do
      DrawShadow(ACanvas, DrawList[I], OffsetX, OffsetY);

    // 4. Draw Objects (Pass 2)
    for I := 0 to DrawList.Count - 1 do
      DrawObject(ACanvas, DrawList[I], OffsetX, OffsetY);

    // 5. Draw Particles on top
    DrawParticles(ACanvas, OffsetX, OffsetY);
  finally
    DrawList.Free;
  end;
end;

procedure TSkiCatIsoGame.SafeInvalidate;
begin
  // Thread-safe UI invalidation.
  // We must check ComponentState to avoid calling Repaint while the component
  // is being destroyed.
  if csDestroying in ComponentState then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) and Assigned(Self) then
      begin
        Redraw;
        Repaint;
      end
    end);
end;

procedure TSkiCatIsoGame.StartThread;
begin
  if Assigned(FThread) then Exit;

  // Run the game loop on a background thread to decouple it from the UI thread.
  // This ensures smooth physics even if the UI thread is briefly busy.
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LastTime, NowTime, DeltaMS: Cardinal;
    begin
      LastTime := TThread.GetTickCount;
      while not TThread.CheckTerminated do
      begin
        NowTime := TThread.GetTickCount;
        DeltaMS := NowTime - LastTime;
        if DeltaMS = 0 then DeltaMS := 1; // Prevent division by zero
        LastTime := NowTime;

        if FActive then
        begin
          DoPhysicsUpdate(DeltaMS / 1000);
          SafeInvalidate; // Tell UI thread to redraw
        end;
        Sleep(16); // Cap at roughly 60 FPS (1000/16 ~ 60)
      end;
    end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TSkiCatIsoGame.StopThread;
begin
  FActive := False;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(50); // Give the thread a brief moment to exit its loop cleanly
  end;
end;

constructor TSkiCatIsoGame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Initialize thread synchronization
  FLock := TCriticalSection.Create;

  // FMX Control setup
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;

  // Game state initialization
  FActive := True;
  FAnimPhase := 0;
  FHasTarget := False;
  FIsMoving := False;

  // FObjects owns its items, so freeing the list frees the objects.
  FObjects := TObjectList<TGameObject>.Create(True);
  FParticles := TList<TParticle>.Create;

  // Create player placeholder
  FPlayer := TGameObject.Create;
  FPlayer.Kind := okCat;
  FPlayer.SizeX := 1; FPlayer.SizeY := 1;

  GenerateWorld;
  StartThread;
end;

destructor TSkiCatIsoGame.Destroy;
begin
  StopThread;

  // Important: FObjects owns its items. If we just free FObjects, it will try
  // to free FPlayer and FMouse. We must extract them first to avoid Access Violations.
  FObjects.Extract(FPlayer);
  FPlayer.Free;
  FObjects.Extract(FMouse);
  FMouse.Free;

  // Now safe to free the list and remaining objects
  FreeAndNil(FObjects);
  FreeAndNil(FParticles);
  FreeAndNil(FLock);
  inherited;
end;

procedure TSkiCatIsoGame.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  GameKey: Byte;
begin
  GameKey := 0;
  // Map Arrow Keys
  case Key of
    vkLeft, vkRight, vkUp, vkDown: GameKey := Key;
  end;
  // Map WASD
  if GameKey = 0 then
  begin
    case KeyChar of
      'A', 'a': GameKey := Ord('A');
      'D', 'd': GameKey := Ord('D');
      'W', 'w': GameKey := Ord('W');
      'S', 's': GameKey := Ord('S');
    end;
  end;

  // Thread-safe add to pressed keys set
  if GameKey > 0 then
  begin
    FLock.Acquire;
    try Include(FKeys, GameKey); finally FLock.Release; end;
    Key := 0; // Suppress default FMX handling
  end;
  inherited;
end;

procedure TSkiCatIsoGame.KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  GameKey: Byte;
begin
  GameKey := 0;
  case Key of
    vkLeft, vkRight, vkUp, vkDown: GameKey := Key;
  end;
  if GameKey = 0 then
  begin
    case KeyChar of
      'A', 'a': GameKey := Ord('A');
      'D', 'd': GameKey := Ord('D');
      'W', 'w': GameKey := Ord('W');
      'S', 's': GameKey := Ord('S');
    end;
  end;

  // Thread-safe remove from pressed keys set
  if GameKey > 0 then
  begin
    FLock.Acquire;
    try Exclude(FKeys, GameKey); finally FLock.Release; end;
    Key := 0;
  end;
  inherited;
end;

end.
