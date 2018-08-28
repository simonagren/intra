export interface ITermSets {
    _ObjectType_: string;
    _Child_Items_: ITermSet[];
}

export interface ITermSet {
    _ObjectType_: string;
    _ObjectIdentity_: string;
    Id: string;
    Name: string;
    Description: string;
    Terms: ITerms;
}

export interface ITerms {
    _ObjectType_: string;
    _Child_Items_: ITerm[];
}

export interface ITerm {
  _ObjectType_: string;
  _ObjectIdentity_: string;
  CreatedDate: string;
  CustomProperties: any;
  CustomSortOrder: string;
  Description: string;
  Id: string;
  IsAvailableForTagging: boolean;
  IsDeprecated: boolean;
  IsKeyword: boolean;
  IsPinned: boolean;
  IsPinnedRoot: boolean;
  IsReused: boolean;
  IsRoot: boolean;
  IsSourceTerm: boolean;
  LastModifiedDate: string;
  LocalCustomProperties: any;
  Name: string;
  Owner: string;
  PathOfTerm: string;
  PathDepth?: number;
  Terms: ITerm[];
  TermsCount: number;
}