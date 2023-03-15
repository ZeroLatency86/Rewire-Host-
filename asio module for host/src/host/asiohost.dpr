program asiohost;

uses
  Forms,
  main in 'main.pas' {MainForm},
  AsioList in '..\asiolist.pas',
  Asio in '..\asio.pas',
  OpenASIO in '..\openasio\OpenASIO.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
