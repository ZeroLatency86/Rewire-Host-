unit main;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, AsioList, OpenAsio, Asio;


const
     // private message
     PM_ASIO = WM_User + 1652;   // unique we hope

     // asio message(s), as wParam for PM_ASIO
     AM_ResetRequest         = 0;
     AM_BufferSwitch         = 1;     // new buffer index in lParam
     AM_BufferSwitchTimeInfo = 2;     // new buffer index in lParam
                                      // time passed in MainForm.BufferTime
     AM_LatencyChanged       = 3;


     PM_UpdateSamplePos      = PM_ASIO + 1;  // sample pos in wParam (hi) and lParam (lo)


type
  TMainForm = class(TForm)
    DriverCombo: TComboBox;
    DriverInfoBox: TGroupBox;
    ControlPanelBtn: TButton;
    lblName: TLabel;
    lblVersion: TLabel;
    lblInputChannels: TLabel;
    lblOutputChannels: TLabel;
    lblCanSampleRate: TLabel;
    StartBtn: TButton;
    StopBtn: TButton;
    CreateBuffersBtn: TButton;
    DestroyBuffersBtn: TButton;
    lblBufferSizes: TLabel;
    GroupBox1: TGroupBox;
    lblInputLatency: TLabel;
    lblOutputLatency: TLabel;
    GroupBox2: TGroupBox;
    lblLeftChannelType: TLabel;
    lblRightChannelType: TLabel;
    GroupBox3: TGroupBox;
    lblSamplePos: TLabel;
    lblTime: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure DriverComboChange(Sender: TObject);
    procedure ControlPanelBtnClick(Sender: TObject);
    procedure StartBtnClick(Sender: TObject);
    procedure StopBtnClick(Sender: TObject);
    procedure CreateBuffersBtnClick(Sender: TObject);
    procedure DestroyBuffersBtnClick(Sender: TObject);
  private
    procedure ChangeEnabled;
    procedure CloseDriver;
    procedure BufferSwitch(index: integer);
    procedure BufferSwitchTimeInfo(index: integer; const params: TAsioTime);
  public
    driverlist        : TAsioDriverList;
    Driver            : IOpenAsio;
    BuffersCreated    : boolean;
    IsStarted         : boolean;
    callbacks         : TASIOCallbacks;
    bufferinfo        : PAsioBufferInfo;
    BufferTime        : TAsioTime;
    ChannelInfos      : array[0..1] of TASIOChannelInfo;
    SampleRate        : TASIOSampleRate;
    CurrentBufferSize : integer;
    procedure PMAsio(var Message: TMessage); message PM_ASIO;
    procedure PMUpdateSamplePos(var Message: TMessage); message PM_UpdateSamplePos;
  end;

var
  MainForm: TMainForm;



implementation

{$R *.DFM}

function ChannelTypeToString(vType: TAsioSampleType): AnsiString;
begin
  Result := '';
  case vType of
    ASIOSTInt16MSB   :  Result := 'Int16MSB';
    ASIOSTInt24MSB   :  Result := 'Int24MSB';
    ASIOSTInt32MSB   :  Result := 'Int32MSB';
    ASIOSTFloat32MSB :  Result := 'Float32MSB';
    ASIOSTFloat64MSB :  Result := 'Float64MSB';

    // these are used for 32 bit data buffer, with different alignment of the data inside
    // 32 bit PCI bus systems can be more easily used with these
    ASIOSTInt32MSB16 :  Result := 'Int32MSB16';
    ASIOSTInt32MSB18 :  Result := 'Int32MSB18';
    ASIOSTInt32MSB20 :  Result := 'Int32MSB20';
    ASIOSTInt32MSB24 :  Result := 'Int32MSB24';

    ASIOSTInt16LSB   :  Result := 'Int16LSB';
    ASIOSTInt24LSB   :  Result := 'Int24LSB';
    ASIOSTInt32LSB   :  Result := 'Int32LSB';
    ASIOSTFloat32LSB :  Result := 'Float32LSB';
    ASIOSTFloat64LSB :  Result := 'Float64LSB';

    // these are used for 32 bit data buffer, with different alignment of the data inside
    // 32 bit PCI bus systems can more easily used with these
    ASIOSTInt32LSB16 :  Result := 'Int32LSB16';
    ASIOSTInt32LSB18 :  Result := 'Int32LSB18';
    ASIOSTInt32LSB20 :  Result := 'Int32LSB20';
    ASIOSTInt32LSB24 :  Result := 'Int32LSB24';
  end;
end;

// asio callbacks

procedure AsioBufferSwitch(doubleBufferIndex: longint; directProcess: TASIOBool); cdecl;
begin
  case directProcess of
    ASIOFalse :  PostMessage(MainForm.Handle, PM_ASIO, AM_BufferSwitch, doubleBufferIndex);
    ASIOTrue  :  MainForm.BufferSwitch(doubleBufferIndex);
  end;
end;

procedure AsioSampleRateDidChange(sRate: TASIOSampleRate); cdecl;
begin
  MessageDlg('The sample rate has been changed to ' + FloatToStr(sRate), mtInformation, [mbOK], 0);
end;

function AsioMessage(selector, value: longint; message: pointer; opt: pdouble): longint; cdecl;
begin
  Result := 0;

  case selector of
    kAsioSelectorSupported    :   // return 1 if a selector is supported
      begin
        case value of
          kAsioEngineVersion        :  Result := 1;
          kAsioResetRequest         :  Result := 1;
          kAsioBufferSizeChange     :  Result := 0;
          kAsioResyncRequest        :  Result := 1;
          kAsioLatenciesChanged     :  Result := 1;
          kAsioSupportsTimeInfo     :  Result := 1;
          kAsioSupportsTimeCode     :  Result := 1;
          kAsioSupportsInputMonitor :  Result := 0;
        end;
      end;
    kAsioEngineVersion        :  Result := 2;   // ASIO 2 is supported
    kAsioResetRequest         :
      begin
        PostMessage(MainForm.Handle, PM_Asio, AM_ResetRequest, 0);
        Result := 1;
      end;
    kAsioBufferSizeChange     :
      begin
        PostMessage(MainForm.Handle, PM_Asio, AM_ResetRequest, 0);
        Result := 1;
      end;
    kAsioResyncRequest        :  ;
    kAsioLatenciesChanged     :
      begin
        PostMessage(MainForm.Handle, PM_Asio, AM_LatencyChanged, 0);
        Result := 1;
      end;
    kAsioSupportsTimeInfo     :  Result := 1;
    kAsioSupportsTimeCode     :  Result := 0;
    kAsioSupportsInputMonitor :  ;
  end;
end;

function AsioBufferSwitchTimeInfo(var params: TASIOTime; doubleBufferIndex: longint; directProcess: TASIOBool): PASIOTime; cdecl;
begin
  case directProcess of
    ASIOFalse :
      begin
        MainForm.BufferTime := params;
        PostMessage(MainForm.Handle, PM_ASIO, AM_BufferSwitchTimeInfo, doubleBufferIndex);
      end;
    ASIOTrue  :  MainForm.BufferSwitchTimeInfo(doubleBufferIndex, params);
  end;

  Result := nil;
end;


{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
var
   i: integer;
begin
  bufferinfo := nil;

  // init the driver list
  SetLength(driverlist, 0);
  ListAsioDrivers(driverlist);
  for i := Low(driverlist) to High(driverlist) do
    DriverCombo.Items.Add(driverlist[i].name);

  // set the callbacks record fields
  callbacks.bufferSwitch := AsioBufferSwitch;
  callbacks.sampleRateDidChange := AsioSampleRateDidChange;
  callbacks.asioMessage := AsioMessage;
  callbacks.bufferSwitchTimeInfo := AsioBufferSwitchTimeInfo;

  // set the driver itself to nil for now
  Driver := nil;
  BuffersCreated := FALSE;
  IsStarted := FALSE;

  // and make sure all controls are enabled or disabled
  ChangeEnabled;  
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  CloseDriver;
  SetLength(driverlist, 0);
end;

procedure TMainForm.DriverComboChange(Sender: TObject);
begin
  if Driver <> nil then
    CloseDriver;

  if DriverCombo.ItemIndex >= 0 then
  begin
    if OpenAsioCreate(driverList[DriverCombo.ItemIndex].id, Driver) then
      if (Driver <> nil) then
        if not Succeeded(Driver.Init(Handle)) then
          Driver := nil;  // RELEASE
  end;

  ChangeEnabled;
end;

procedure TMainForm.ChangeEnabled;
var
   buf       : array[0..255] of AnsiChar;
   version   : integer;
   inp, outp : integer;
   hr        : HResult;
   min, max, pref, gran : integer;
   i                    : integer;
   can44100, can48000   : boolean;
const
     boolstrings : array[0..1] of AnsiString = ('no', 'yes');
begin
  ControlPanelBtn.Enabled := (Driver <> nil);

  CreateBuffersBtn.Enabled := (Driver <> nil) and not BuffersCreated;
  DestroyBuffersBtn.Enabled := BuffersCreated;
  StartBtn.Enabled := (Driver <> nil) and BuffersCreated and not IsStarted;
  StopBtn.Enabled := IsStarted;

  lblName.Caption := 'name : ';
  lblVersion.Caption := 'version : ';
  lblInputChannels.Caption := 'input channels : ';
  lblOutputChannels.Caption := 'output channels : ';
  lblCanSampleRate.Caption := 'can samplerate : ';
  lblInputLatency.Caption := 'input : ';
  lblOutputLatency.Caption := 'output : ';
  lblLeftChannelType.Caption := 'left type : ';
  lblRightChannelType.Caption := 'right type : ';

  if Driver <> nil then
  begin
    Driver.GetDriverName(buf);
    lblName.Caption := 'name : ' + buf;
    version := Driver.GetDriverVersion;
    lblVersion.Caption := 'version : $' + Format('%.8x', [version]);
    Driver.GetChannels(inp, outp);
    lblInputChannels.Caption := 'input channels : ' + IntToStr(inp);
    lblOutputChannels.Caption := 'output channels : ' + IntToStr(outp);
    hr := Driver.CanSampleRate(44100);
    can44100 := (hr = ASE_OK);
    hr := Driver.CanSampleRate(48000);
    can48000 := (hr = ASE_OK);
    lblCanSampleRate.Caption := Format('can samplerate : 44100 <%s> 48000 <%s>', [boolstrings[Ord(can44100)], boolstrings[Ord(can48000)]]);
    Driver.GetBufferSize(min, max, pref, gran);
    lblBufferSizes.Caption := Format('buffer sizes : min=%d max=%d pref=%d gran=%d', [min, max, pref, gran]);

    if BuffersCreated then
    begin
      Driver.GetLatencies(inp, outp);
      lblInputLatency.Caption := 'input : ' + IntToStr(inp);
      lblOutputLatency.Caption := 'output : ' + IntToStr(outp);

      // now get all the buffer details, sample word length, name, word clock group and activation
      for i := 0 to 1 do
      begin
        ChannelInfos[i].channel := i;
        ChannelInfos[i].isInput := ASIOFalse;   //  output
        Driver.GetChannelInfo(ChannelInfos[i]);
        if i = 0 then
          lblLeftChannelType.Caption := 'left type : ' + ChannelTypeToString(ChannelInfos[i].vType)
        else
          lblRightChannelType.Caption := 'right type : ' + ChannelTypeToString(ChannelInfos[i].vType);
      end;
    end;
  end;
end;

procedure TMainForm.ControlPanelBtnClick(Sender: TObject);
begin
  if (Driver <> nil) then
    Driver.ControlPanel;
end;

procedure TMainForm.CloseDriver;
begin
  if Driver <> nil then
  begin
    if IsStarted then
      StopBtn.Click;
    if BuffersCreated then
      DestroyBuffersBtn.Click;
    Driver := nil;  // RELEASE;
  end;

  ChangeEnabled;
end;

procedure TMainForm.StartBtnClick(Sender: TObject);
begin
  if Driver = nil then
    Exit;

  IsStarted := (Driver.Start = ASE_OK);
  ChangeEnabled;
end;

procedure TMainForm.StopBtnClick(Sender: TObject);
begin
  if Driver = nil then
    Exit;

  if IsStarted then
  begin
    Driver.Stop;
    IsStarted := FALSE;
  end;
  
  ChangeEnabled;
end;

procedure TMainForm.CreateBuffersBtnClick(Sender: TObject);
var
   min, max, pref, gran : integer;
   currentbuffer        : PAsioBufferInfo;
   i                    : integer;
begin
  if Driver = nil then
    Exit;

  if BuffersCreated then
    DestroyBuffersBtn.Click;

  Driver.GetBufferSize(min, max, pref, gran);

  // two output channels
  GetMem(bufferinfo, SizeOf(TAsioBufferInfo)*2);
  currentbuffer := bufferinfo;
  for i := 0 to 1 do
  begin
    currentbuffer^.isInput := ASIOFalse;  // create an output buffer
    currentbuffer^.channelNum := i;
    currentbuffer^.buffers[0] := nil;
    currentbuffer^.buffers[1] := nil;
    inc(currentbuffer);
  end;

  // actually create the buffers
  BuffersCreated := (Driver.CreateBuffers(bufferinfo, 2, pref, callbacks) = ASE_OK);
  if BuffersCreated then
    CurrentBufferSize := pref
  else
    CurrentBufferSize := 0;

  ChangeEnabled;
end;

procedure TMainForm.DestroyBuffersBtnClick(Sender: TObject);
begin
  if (Driver = nil) or not BuffersCreated then
    Exit;

  if IsStarted then
    StopBtn.Click;

  FreeMem(bufferinfo);
  bufferinfo := nil;
  Driver.DisposeBuffers;
  BuffersCreated := FALSE;
  CurrentBufferSize := 0;

  ChangeEnabled;
end;

procedure TMainForm.PMAsio(var Message: TMessage);
var
   inp, outp: integer;
begin
  case Message.WParam of
    AM_ResetRequest         :  DriverComboChange(DriverCombo);                    // restart the driver
    AM_BufferSwitch         :  BufferSwitch(Message.LParam);                      // process a buffer
    AM_BufferSwitchTimeInfo :  BufferSwitchTimeInfo(Message.LParam, BufferTime);  // process a buffer with time
    AM_LatencyChanged       :
      if (Driver <> nil) then
      begin
        Driver.GetLatencies(inp, outp);
        lblInputLatency.Caption := 'input : ' + IntToStr(inp);
        lblOutputLatency.Caption := 'output : ' + IntToStr(outp);
      end;
  end;
end;

procedure TMainForm.BufferSwitch(index: integer);
begin
  FillChar(BufferTime, SizeOf(TAsioTime), 0);

  // get the time stamp of the buffer, not necessary if no
  // synchronization to other media is required
  if Driver.GetSamplePosition(BufferTime.timeInfo.samplePosition, BufferTime.timeInfo.systemTime) = ASE_OK then
    BufferTime.timeInfo.flags := kSystemTimeValid or kSamplePositionValid;

  BufferSwitchTimeInfo(index, BufferTime);
end;

procedure TMainForm.BufferSwitchTimeInfo(index: integer; const params: TAsioTime);
var
   i, ndx        : integer;
   info          : PAsioBufferInfo;
   outputInt16   : PSmallint;
   outputInt32   : PInteger;
   outputFloat32 : PSingle;
begin
  // this is where processing occurs, with the buffers provided by Driver.CreateBuffers
  // beware of the buffer output format, of course
  info := BufferInfo;

  for i := 0 to 1 do
  begin
    case ChannelInfos[i].vType of
      ASIOSTInt16MSB   :  ;
      ASIOSTInt24MSB   :  ;
      ASIOSTInt32MSB   :  ;
      ASIOSTFloat32MSB :  ;
      ASIOSTFloat64MSB :  ;

      ASIOSTInt32MSB16 :  ;
      ASIOSTInt32MSB18 :  ;
      ASIOSTInt32MSB20 :  ;
      ASIOSTInt32MSB24 :  ;

      ASIOSTInt16LSB   :
        begin
          // example:
          outputInt16 := info^.buffers[index];
          for ndx := 0 to CurrentBufferSize-1 do
          begin
            outputInt16^ := 0;   // here we actually fill the output buffer (with zeroes)
            inc(outputInt16);
          end;
        end;
      ASIOSTInt24LSB   :  ;
      ASIOSTInt32LSB   :  
        begin
          // example:
          outputInt32 := info^.buffers[index];
          for ndx := 0 to CurrentBufferSize-1 do
          begin
            outputInt32^ := 0;   // here we actually fill the output buffer (with zeroes)
            inc(outputInt32);
          end;
        end;
      ASIOSTFloat32LSB :
        begin
          // example:
          outputFloat32 := info^.buffers[index];
          for ndx := 0 to CurrentBufferSize-1 do
          begin
            outputFloat32^ := 0;   // here we actually fill the output buffer (with zeroes)
            inc(outputFloat32);
          end;
        end;
      ASIOSTFloat64LSB :  ;
      ASIOSTInt32LSB16 :  ;
      ASIOSTInt32LSB18 :  ;
      ASIOSTInt32LSB20 :  ;
      ASIOSTInt32LSB24 :  ;
    end;

    inc(info);  // don't forget to go to the next buffer in this loop
  end;


  // tell the interface that the sample position has changed
  PostMessage(Handle, PM_UpdateSamplePos, params.timeInfo.samplePosition.hi, params.timeInfo.samplePosition.lo);

  Driver.OutputReady;    // some asio drivers require this  
end;

procedure TMainForm.PMUpdateSamplePos(var Message: TMessage);
var
   Samples     : TAsioSamples;
   SampleCount : Int64;
   seconds     : Int64;
   minutes     : Int64;
   hours       : Int64;
begin
  Samples.hi := Message.wParam;
  Samples.lo := Message.lParam;
  SampleCount := ASIOSamplesToInt64(Samples);
  lblSamplePos.Caption := Format('sample pos : %d (hi:%d) (lo:%d)', [SampleCount, Samples.hi, Samples.lo]);

  seconds := SampleCount div 44100;
  hours := seconds div 3600;
  minutes := (seconds mod 3600) div 60;
  seconds := seconds mod 60;
  lblTime.Caption := Format('time : %d:%.2d:%.2d', [hours, minutes, seconds]);
end;

end.
