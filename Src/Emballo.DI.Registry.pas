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

unit Emballo.DI.Registry;

interface

uses
  Emballo.DI.Factory, Emballo.DI.Register, Emballo.DI.RegisterImpl, Emballo.Rtti;

{ Returns a registered IFactory that can handle the specified GUID. If none can
  be found, return Nil. }
function GetFactoryFor(GUID: TGUID): IFactory;

{ Starts the registration of a generic IFactory }
function RegisterFactory(const Factory: IFactory): IRegister; overload;

{ Start the registration of a factory that will dynamically build an instance
  given its metaclass }
function RegisterFactory(const GUID: TGUID; Implementor: TClass): IRegister; overload;

{ Starts the registration of a factory that will always return a pre defined
  instance }
function RegisterFactory(const GUID: TGUID; const Instance: IInterface): IRegister; overload;

{ Starts the registration of a factory which will dynamically build an object
  that binds the GUID interface to the specified dll, using Emballo's
  DllWrapper features }
function RegisterFactoryDll(const GUID: TGUID; const DllName: String): IRegister;

{ Removes all of the already registered factories }
procedure ClearRegistry;

implementation

uses
  Generics.Collections, Emballo.DI.DynamicFactory, Emballo.DI.PreBuiltFactory, SysUtils,
  Emballo.DI.PoolFactory, Emballo.DI.DllWrapperFactory;

var
  Registry: TList<IFactory>;

function RegisterFactory(const Factory: IFactory): IRegister;
begin
  Result := TRegister.Create(Factory, Registry);
end;

function RegisterFactory(const GUID: TGUID; Implementor: TClass): IRegister;
begin
  Result := RegisterFactory(TDynamicFactory.Create(GUID, Implementor));
end;

function RegisterFactory(const GUID: TGUID; const Instance: IInterface): IRegister;
begin
  Result := RegisterFactory(TPreBuiltFactory.Create(GUID, Instance));
end;

function RegisterFactoryDll(const GUID: TGUID; const DllName: String): IRegister;
begin
  Result := RegisterFactory(TDllWrapperFactory.Create(GetTypeInfoFromGUID(GUID),
    DllName));
end;

function GetFactoryFor(GUID: TGUID): IFactory;
var
  Factory: IFactory;
begin
  for Factory in Registry do
  begin
    if IsEqualGUID(GUID, Factory.GUID) then
      Exit(Factory);
  end;

  Result := Nil;
end;

procedure ClearRegistry;
begin
  Registry.Clear;
end;

initialization
Registry := TList<IFactory>.Create;

finalization
Registry.Free;

end.
