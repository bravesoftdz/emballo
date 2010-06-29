{   Copyright 2010 - Magno Machado Paulo (magnomp@gmail.com)

    This file is part of Emballo.

    Emballo is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    Emballo is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with Emballo.
    If not, see <http://www.gnu.org/licenses/>. }

unit Emballo.SynteticClass;

interface

uses
  Emballo.RuntimeCodeGeneration.AsmBlock;

type
  TInstanceFinalizer = reference to procedure(const Instance: TObject);

  PClass = ^TClass;
  PSafeCallException = function  (Self: TObject; ExceptObject:
    TObject; ExceptAddr: Pointer): HResult;
  PAfterConstruction = procedure (Self: TObject);
  PBeforeDestruction = procedure (Self: TObject);
  PDispatch          = procedure (Self: TObject; var Message);
  PDefaultHandler    = procedure (Self: TObject; var Message);
  PNewInstance       = function  (Self: TClass) : TObject;
  PFreeInstance      = procedure (Self: TObject);
  TDestroy           = procedure (OuterMost: ShortInt) of object;
  TObjectVirtualMethods = packed record
    A, B, C: Pointer;
    SafeCallException : PSafeCallException;
    AfterConstruction : PAfterConstruction;
    BeforeDestruction : PBeforeDestruction;
    Dispatch          : PDispatch;
    DefaultHandler    : PDefaultHandler;
    NewInstance       : PNewInstance;
    FreeInstance      : PFreeInstance;
    Destroy           : Pointer;
  end;
  PClassRec = ^TClassRec;
  TClassRec = packed record
    SelfPtr           : TClass;
    IntfTable         : Pointer;
    AutoTable         : Pointer;
    InitTable         : Pointer;
    TypeInfo          : Pointer;
    FieldTable        : Pointer;
    MethodTable       : Pointer;
    DynamicTable      : Pointer;
    ClassName         : PShortString;
    InstanceSize      : Longint;
    Parent            : PClass;
    DefaultVirtualMethods: TObjectVirtualMethods;
  end;

  TSynteticClassRec = packed record
    AdicionalInstanceSize: Integer;
    ClassRec: TClassRec;
  end;
  PSynteticClassRec = ^TSynteticClassRec;

  TVmtEntry = record
    Index: Integer;
    Address: Pointer;
  end;

  { Manages a runtime-generated metaclass }
  TSynteticClass = class
  private
    FClassName: ShortString;
    FClassRec: PSynteticClassRec;
    FFinalizer: TInstanceFinalizer;
    FOldDestroy: Pointer;
    FNewDestroy: TAsmBlock;
    function GetMetaclass: TClass;
    function GetVirtualMethodAddress(const Index: Integer): Pointer;
    procedure SetVirtualMethodAddress(const Index: Integer; const Value: Pointer);
    function EnumerateVirtualMethods(const ParentClass: TClass): TArray<TVmtEntry>;
    procedure CreateNewDestroy;
    procedure NewDestroy(Instance: TObject; OuterMost: ShortInt);
  public
    constructor Create(const ClassName: ShortString; const Parent: TClass;
      const AditionalInstanceSize: Integer);
    destructor Destroy; override;

    { Returns the new metaclass }
    property Metaclass: TClass read GetMetaclass;

    property VirtualMethodAddress[const Index: Integer]: Pointer read
      GetVirtualMethodAddress write SetVirtualMethodAddress;

    property Finalizer: TInstanceFinalizer read FFinalizer write FFinalizer;
  end;

function GetAditionalData(const Instance: TObject): Pointer;
procedure SetAditionalData(const Instance: TObject; const Data);

implementation

uses
  Rtti, TypInfo, Generics.Defaults, Generics.Collections;

function GetAditionalInstanceSize(const SynteticClass: TClass): Integer;
var
  SynteticClassRec: PSynteticClassRec;
begin
  SynteticClassRec := PSynteticClassRec(Pointer(Integer(SynteticClass) - SizeOf(TSynteticClassRec)));

  Result := SynteticClassRec.AdicionalInstanceSize;
end;

function GetAditionalData(const Instance: TObject): Pointer;
begin
  { RTL considers an implicit TMonitor field as the last field on the object }
  Result := Pointer(Integer(Instance) + Instance.InstanceSize -
    GetAditionalInstanceSize(Instance.ClassType) - SizeOf(Pointer));
end;

procedure SetAditionalData(const Instance: TObject; const Data);
begin
  Move(Data, GetAditionalData(Instance)^, GetAditionalInstanceSize(Instance.ClassType));
end;

{ TSynteticClass }

constructor TSynteticClass.Create(const ClassName: ShortString; const Parent: TClass;
  const AditionalInstanceSize: Integer);
var
  ParentClassRec: PClassRec;
  VmtEntries: TArray<TVmtEntry>;
  NumVmtEntries: Integer;
begin
  VmtEntries := EnumerateVirtualMethods(Parent);
  NumVmtEntries := VmtEntries[High(VmtEntries)].Index + 1;

  ParentClassRec := PClassRec(Parent);
  Dec(ParentClassRec);

  FClassName := ClassName;

  GetMem(FClassRec, SizeOf(TSynteticClassRec) + NumVmtEntries*SizeOf(Pointer));

  FClassRec.AdicionalInstanceSize := AditionalInstanceSize;

  Move(ParentClassRec^, FClassRec.ClassRec, SizeOf(TClassRec));
  GetMem(FClassRec.ClassRec.Parent, SizeOf(Pointer));
  FClassRec.ClassRec.ClassName := @FClassName;
  FClassRec.ClassRec.InstanceSize := Parent.InstanceSize + AditionalInstanceSize;
  Pointer(FClassRec.ClassRec.Parent^) := Parent;

  FOldDestroy := FClassRec.ClassRec.DefaultVirtualMethods.Destroy;
  CreateNewDestroy;
  FClassRec.ClassRec.DefaultVirtualMethods.Destroy := FNewDestroy.Block;
end;

procedure TSynteticClass.CreateNewDestroy;
begin
  FNewDestroy := TAsmBlock.Create;

  { mov ecx, edx }
  FNewDestroy.PutB([$8B, $CA]);

  { mov edx, Self }
  FNewDestroy.PutB($BA); FNewDestroy.PutI(Integer(Self));

  { xchg eax, dcx }
  FNewDestroy.PutB($92);

  FNewDestroy.GenJmp(@TSynteticClass.NewDestroy);

  FNewDestroy.Compile;
end;

destructor TSynteticClass.Destroy;
begin
  FNewDestroy.Free;
  FreeMem(FClassRec.ClassRec.Parent);
  FreeMem(FClassRec);
  inherited;
end;

function TSynteticClass.EnumerateVirtualMethods(
  const ParentClass: TClass): TArray<TVmtEntry>;
var
  Ctx: TRttiContext;
  RttiType: TRttiType;
  Methods: TArray<TRttiMethod>;
  Method: TRttiMethod;
begin
  SetLength(Result, 0);
  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(ParentClass);

    Methods := RttiType.GetMethods;

    for Method in Methods do
    begin
      if Method.DispatchKind = dkVtable then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)].Index := Method.VirtualIndex;
        Result[High(Result)].Address := Method.CodeAddress;
      end;
    end;
  finally
    Ctx.Free;
  end;

  TArray.Sort<TVmtEntry>(Result, TComparer<TVmtEntry>.Construct(function(const Left, Right: TVmtEntry): Integer
  begin
    Result := Left.Index - Right.Index;
  end));
end;

function TSynteticClass.GetMetaclass: TClass;
begin
  Result := TClass(Pointer(Integer(@FClassRec.ClassRec) + SizeOf(TClassRec)));
end;

function TSynteticClass.GetVirtualMethodAddress(const Index: Integer): Pointer;
begin

end;

procedure TSynteticClass.NewDestroy(Instance: TObject; OuterMost: ShortInt);
var
  OldDestroy: TDestroy;
begin
  { Save the data needed to call the old destructor before calling the Finalizer,
    because the Finalizer may free this TSynteticClass }
  TMethod(OldDestroy).Data := Instance;
  TMethod(OldDestroy).Code := FOldDestroy;

  if Assigned(Finalizer) then
    Finalizer(Instance);

  OldDestroy(OuterMost);
end;

procedure TSynteticClass.SetVirtualMethodAddress(const Index: Integer;
  const Value: Pointer);
var
  Vmt: PPointer;
begin
  Vmt := PPointer(@FClassRec.ClassRec.DefaultVirtualMethods);
  Inc(Vmt, Index + 11);
  Vmt^ := Value;
end;

end.