{   Copyright 2010 - Magno Machado Paulo (magnomp@gmail.com)

    This file is part of Emballo.

    Emballo is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Emballo is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Foobar.  If not, see <http://www.gnu.org/licenses/>. }

unit EbCore;

interface

uses
  SysUtils;

type
  TEmballo = class
  public
    function Get<ServiceInterface>: ServiceInterface;
  end;

  ECouldNotBuild = class(Exception)
  public
    constructor Create(const GUID: TGUID);
  end;

function Emballo: TEmballo;

implementation

uses
  Rtti, EbInstantiator, EbRegistry, EbUtil, TypInfo;

function Emballo: TEmballo;
begin
  Result := Nil;
end;

{ ECouldNotBuild }

constructor ECouldNotBuild.Create(const GUID: TGUID);
var
  Ctx: TRttiContext;
  RttiType: TRttiInterfaceType;
  InterfaceName: String;
begin
  Ctx := TRttiContext.Create;
  try
    RttiType := GetRttiTypeFromGUID(Ctx, GUID);
    InterfaceName := RttiType.Name;
    inherited Create('Could not instantiate ' + InterfaceName);
  finally
    Ctx.Free;
  end;
end;

{ TEmballo }

function TEmballo.Get<ServiceInterface>: ServiceInterface;
var
  Service: IInterface;
  Ctx: TRttiContext;
  ServiceRttiType: TRttiType;
  ServiceGUID: TGUID;
begin
  Ctx := TRttiContext.Create;
  try
    ServiceRttiType := Ctx.GetType(TypeInfo(ServiceInterface));
    if ServiceRttiType.TypeKind <> tkInterface then
      raise EArgumentException.Create('Emballo.Get must be called only with interface types');

    ServiceGUID := (ServiceRttiType as TRttiInterfaceType).GUID;
    if not TryBuild(ServiceGUID, Service) then
      raise ECouldNotBuild.Create(ServiceGUID);

    Supports(Service, ServiceGUID, Result);
  finally
    Ctx.Free;
  end;
end;

end.