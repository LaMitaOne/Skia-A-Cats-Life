unit Unit1;

interface
uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, SkiaCatsLife;
type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    { Private-Deklarationen }
  public
    { Public-Deklarationen }
  end;
var
  Form1: TForm1;
implementation
{$R *.fmx}
procedure TForm1.FormCreate(Sender: TObject);
var
  Game: TSkiCatIsoGame;
begin
  Game := TSkiCatIsoGame.Create(Self);
  Game.Parent := Self;
  Game.Align := TAlignLayout.Client;
  Game.SetFocus;
end;
end.
