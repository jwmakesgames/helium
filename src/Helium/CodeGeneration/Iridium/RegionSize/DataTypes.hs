module Helium.CodeGeneration.Iridium.RegionSize.DataTypes
where

import Lvm.Common.Id
import Lvm.Common.IdMap

import Helium.CodeGeneration.Iridium.BindingGroup
import Helium.CodeGeneration.Iridium.Data
import Helium.CodeGeneration.Core.TypeEnvironment

import Helium.CodeGeneration.Iridium.RegionSize.Annotation
import Helium.CodeGeneration.Iridium.RegionSize.Utils
import Helium.CodeGeneration.Iridium.RegionSize.Sort
import Helium.CodeGeneration.Iridium.RegionSize.Constraints

import GHC.Stack

import Data.Either (rights)

----------------------------------------------------------------
-- Data type environment
----------------------------------------------------------------

data DataSort = Complex !Sort | Analyzed !Sort
instance Show DataSort where
  show (Complex  s) = "[C] " ++ show s
  show (Analyzed s) = "[A] " ++ show s

data DataTypeEnv = DataTypeEnv { 
  dtSorts     :: !(IdMap DataSort),    -- ^ Datatype id -> sort, sort assignment
  dtRegions   :: !(IdMap DataSort),    -- ^ Datatype id -> sort, region assignment
  dtStructs   :: !(IdMap Annotation),  -- ^ Constructor id -> constructor annotation
  dtDestructs :: !(IdMap [Annotation]) -- ^ Constructor id -> destructor annotation
}

emptyDEnv :: DataTypeEnv
emptyDEnv = DataTypeEnv emptyMap emptyMap emptyMap emptyMap

---------------------------------------------------------------
-- Data types lookup functions
----------------------------------------------------------------

-- | Lookup a datatype in the datatype environment
lookupDataType :: HasCallStack => Id -> DataTypeEnv -> DataSort
lookupDataType name dEnv = case lookupMap name (dtSorts dEnv) of
                              Nothing -> rsError $ "lookupDataType: Datatype not in environment: " ++ show name
                              Just ds -> ds

-- | Lookup a datatype in the datatype environment
lookupDataTypeRegs :: HasCallStack => Id -> DataTypeEnv -> DataSort
lookupDataTypeRegs name dEnv = case lookupMap name (dtRegions dEnv) of
                                 Nothing -> rsError $ "lookupDataType: Datatype not in environment: " ++ show name
                                 Just ds -> ds

-- | Lookup a datatype constructor in the datatype environment
lookupStruct :: HasCallStack => Id -> DataTypeEnv -> Annotation
lookupStruct name dEnv = case lookupMap name (dtStructs dEnv) of
                              Nothing -> rsError $ "lookupStruct: Datatype not in environment: " ++ show name
                              Just ds -> ds

-- | Lookup a datatype constructor in the datatype environment
lookupDestruct :: HasCallStack => Id -> DataTypeEnv -> [Annotation]
lookupDestruct name dEnv = case lookupMap name (dtDestructs dEnv) of
                              Nothing -> rsError $ "lookupDestruct: Datatype not in environment: " ++ show name
                              Just ds -> ds

----------------------------------------------------------------
-- Data types to annotations
----------------------------------------------------------------

-- IDEA: For each field: 
--  - Create bot with sortAssign for non-targets
--  - Create top with sortAssign for targets
--  - What kind of effects does it create?
--    - Unbounded regions for methods in the datatype
-- | Make constructor annotations
makeDataTypeConstructors :: DataTypeEnv -> BindingGroup DataType -> [(Id, Annotation)]
makeDataTypeConstructors dEnv (BindingRecursive decls) = concat $ mapWithIndex unPackDataType decls
  where (Complex (SortTuple dtSrts)) = declarationName (head decls) `lookupDataType` dEnv
        unPackDataType :: Int -> Declaration DataType -> [(Id, Annotation)]
        unPackDataType idx decl = makeDataTypeConstructors' (Complex (dtSrts !! idx)) (declarationValue decl) 
makeDataTypeConstructors dEnv (BindingNonRecursive decl) =
  makeDataTypeConstructors' (declarationName decl `lookupDataType` dEnv) (declarationValue decl)

makeDataTypeConstructors' :: DataSort -> DataType -> [(Id, Annotation)]
makeDataTypeConstructors' (Complex dtSort) dt@(DataType structs) = 
    mapWithIndex makeStructorAnn structs
  where SortTuple dtSrts = sortRemoveQuants dtSort
        makeStructorAnn :: Int -> Declaration DataTypeConstructorDeclaration -> (Id,Annotation)
        makeStructorAnn structIdx strctDecl =
            let size = structorSize strctDecl
                SortTuple structSrt = dtSrts !! structIdx
                -- Wrap with lambdas & quantification
                strctLam = foldr (\i -> ALam (structSrt !! i)) AUnit [0 .. size-1]
            in (declarationName strctDecl, wrapDataTypeQuants dt strctLam)
makeDataTypeConstructors' (Analyzed dtSort) dt@(DataType structs) = 
    mapWithIndex makeStructorAnn structs
  where dtTupSize = length structs
        SortTuple dtSrts = sortRemoveQuants dtSort

        makeStructorAnn :: Int -> Declaration DataTypeConstructorDeclaration -> (Id,Annotation)
        makeStructorAnn structIdx strctDecl =
            let size = structorSize strctDecl
                SortTuple structSrt = dtSrts !! structIdx
                -- Tuple elements
                pre  = (\i -> ABot $ dtSrts !! i)        <$> [0          ..structIdx-1]
                args = ATuple . reverse $ (\i -> AVar i) <$> [0          ..size     -1]
                post = (\i -> ABot $ dtSrts !! i)        <$> [structIdx+1..dtTupSize-1]  
                -- Constructor tuple
                strctTup = ATuple (pre ++ [args] ++ post)
                -- Wrap with lambdas
                strctLam = foldr (\i -> ALam (structSrt !! i)) strctTup [0 .. size-1]
            in (declarationName strctDecl, wrapDataTypeQuants dt strctLam)

-- | Remove sort quantifications
sortRemoveQuants :: Sort -> Sort
sortRemoveQuants (SortQuant s) = sortRemoveQuants s
sortRemoveQuants s = s

-- IDEA: For each field: 
--  - Do not project, return top with sortAssign
--  - Sort on lambda is SortUnit (Datatype should be unit everywhere)
-- | Make destructor annotations
-- | Make constructor annotations
makeDataTypeDestructors :: DataTypeEnv -> BindingGroup DataType -> [(Id, [Annotation])]
makeDataTypeDestructors dEnv (BindingRecursive decls) = concat $ mapWithIndex unPackDataType decls
  where (Complex (SortTuple dtSrts)) = declarationName (head decls) `lookupDataType` dEnv
        unPackDataType :: Int -> Declaration DataType -> [(Id, [Annotation])]
        unPackDataType idx decl = makeDataTypeDestructors' (Complex (dtSrts !! idx)) (declarationValue decl) 
makeDataTypeDestructors dEnv (BindingNonRecursive decl) =
  makeDataTypeDestructors' (declarationName decl `lookupDataType` dEnv) (declarationValue decl)

makeDataTypeDestructors' :: DataSort -> DataType -> [(Id, [Annotation])]
makeDataTypeDestructors' (Complex dtSort) dt@(DataType structs) =
    mapWithIndex makeDestructorAnn structs
  where 
    SortTuple structorSorts = sortRemoveQuants dtSort
    makeDestructorAnn :: Int -> Declaration DataTypeConstructorDeclaration -> (Id,[Annotation])
    makeDestructorAnn idx strctDecl =
        let size = structorSize strctDecl
            SortTuple fieldSorts = structorSorts !! idx
            destrctAnn = (\i -> ALam SortUnit $ ATop (fieldSorts !! i) constrBot) <$> [0 .. size-1]  
        in (declarationName strctDecl, wrapDataTypeQuants dt <$> destrctAnn)
makeDataTypeDestructors' (Analyzed dtSort) dt@(DataType structs) = 
    mapWithIndex makeDestructorAnn structs
  where 
    dtSort' = sortRemoveQuants dtSort
    makeDestructorAnn :: Int -> Declaration DataTypeConstructorDeclaration -> (Id,[Annotation])
    makeDestructorAnn idx strctDecl =
        let size = structorSize strctDecl
            -- Project on elements of constructor
            destrctAnn = (\i -> ALam dtSort' . AProj i . AProj idx $ AVar 0) <$> [0 .. size-1]  
        in (declarationName strctDecl, wrapDataTypeQuants dt <$> destrctAnn)

----------------------------------------------------------------
-- Data type utilitiy functions
----------------------------------------------------------------

structorSize :: Declaration DataTypeConstructorDeclaration -> Int
structorSize (Declaration _ _ _ _ (DataTypeConstructorDeclaration ty _)) =
    let (FunctionType args _) = extractFunctionTypeNoSynonyms ty 
    in length $ rights args

-- | Wrap an annotation in the quantifications for the corresponding datatype
wrapDataTypeQuants :: DataType -> Annotation -> Annotation 
wrapDataTypeQuants dt strctLam = foldr (const AQuant) strctLam (dataTypeQuantors dt)