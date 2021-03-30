module Helium.CodeGeneration.Iridium.RegionSize.Environments
where

import qualified Data.Map as M

import Lvm.Common.Id
import Lvm.Common.IdMap
import Lvm.Core.Type


import Helium.CodeGeneration.Core.TypeEnvironment
import Helium.CodeGeneration.Iridium.Data

import Helium.CodeGeneration.Iridium.RegionSize.Annotation
import Helium.CodeGeneration.Iridium.RegionSize.Constraints
import Helium.CodeGeneration.Iridium.RegionSize.Utils
import Helium.CodeGeneration.Iridium.RegionSize.Sort

import GHC.Stack

----------------------------------------------------------------
-- Type definitions
----------------------------------------------------------------

data GlobalEnv = GlobalEnv !TypeEnvironment !(IdMap (Annotation))
type RegionEnv = M.Map RegionVar ConstrIdx
type BlockEnv  = IdMap Annotation
data LocalEnv  = LocalEnv { 
  lEnvArgCount    :: Int, 
  lEnvAnnotations :: IdMap Annotation 
}
data Envs = Envs GlobalEnv RegionEnv LocalEnv

----------------------------------------------------------------
-- Global environment
----------------------------------------------------------------

-- | Initial analysis environment, sets all functions to top
initialGEnv :: Module -> GlobalEnv
initialGEnv m = GlobalEnv typeEnv functionEnv
  where
    -- Environment is only used for type synonyms
    typeEnv = TypeEnvironment synonyms emptyMap emptyMap

    -- Type synonims
    synonyms :: IdMap Type
    synonyms = mapFromList [(name, tp) | Declaration name _ _ _ (TypeSynonym _ tp) <- moduleTypeSynonyms m]

    -- Functions
    functionEnv :: IdMap Annotation
    functionEnv = mapFromList abstracts

    abstracts :: [(Id, Annotation)]
    abstracts = abstract <$> moduleAbstractMethods m
    abstract (Declaration name _ _ _ (AbstractMethod tp _ _ anns)) = (name, regionSizeAnn tp anns)

    regionSizeAnn :: Type -> [MethodAnnotation] -> Annotation
    regionSizeAnn _ (MethodAnnotateRegionSize a:_) = a
    regionSizeAnn tp (_:xs) = regionSizeAnn tp xs
    regionSizeAnn tp []     = top tp

    -- Top of type
    top :: Type -> Annotation
    top = flip ATop constrBot . sortAssign

----------------------------------------------------------------
-- Block environment
----------------------------------------------------------------

-- | Look up a local variable in the local environment
lookupGlobal :: HasCallStack => Id -> GlobalEnv -> Annotation
lookupGlobal name (GlobalEnv _ vars) = 
  case lookupMap name vars of
    Nothing -> rsError $ "lookupGlobal - Global environment did not contain: " ++ stringFromId name
    Just a  -> a 

-- | Insert a function into the global environment
insertGlobal :: HasCallStack => Id -> Annotation -> GlobalEnv -> GlobalEnv
insertGlobal name ann (GlobalEnv syns fs) =
  case lookupMap name fs of
    Nothing -> GlobalEnv syns $ insertMap name ann fs 
    Just a  -> GlobalEnv syns $ insertMap name (AJoin a ann) $ deleteMap name fs 


-- | Look up a local variable in the local environment
lookupBlock :: BlockName -> BlockEnv -> Annotation
lookupBlock name bEnv = 
  case lookupMap name bEnv of
    Nothing -> rsError $ "lookupBlock -Block variable missing: " ++ stringFromId name
    Just a  -> a 

-- | Look up a local variable in the local environment
lookupLocal :: HasCallStack => Local -> LocalEnv -> Annotation
lookupLocal local (LocalEnv _ lEnv) = 
  case lookupMap (localName local) lEnv of
    Nothing -> rsError $ "lookupLocal - ID not in map: " ++ (stringFromId $ localName local) 
    Just a  -> a

-- | Lookup a global or local variable
lookupVar :: HasCallStack => Variable -> Envs -> Annotation
lookupVar (VarLocal local) (Envs _ _ lEnv) = lookupLocal local lEnv
lookupVar global           (Envs gEnv _ _) = lookupGlobal (variableName global) gEnv


-- | Lookup a region in the region environment, retuns the region if not in env
lookupReg :: HasCallStack => RegionVar -> RegionEnv -> ConstrIdx
lookupReg r rEnv = case M.lookup r rEnv of
                      Nothing -> Region r
                      Just ci -> ci


-- | Insert a local variable
insertLocal :: Id -> Annotation -> LocalEnv -> LocalEnv
insertLocal name ann (LocalEnv argC lEnv) = LocalEnv argC $ insertMap name ann lEnv

-- | Insert a local variable
updateLocal :: Id -> Annotation -> LocalEnv -> LocalEnv
updateLocal name ann (LocalEnv argC lEnv) = LocalEnv argC $ updateMap name ann lEnv

-- | Alter a value in the global map
updateGlobal :: HasCallStack => Id -> Annotation -> GlobalEnv -> GlobalEnv
updateGlobal name ann (GlobalEnv syns fs) = GlobalEnv syns $ updateMap name ann fs


-- | Union the localenv with another annotation map
unionLocalEnv :: LocalEnv -> IdMap Annotation -> LocalEnv
unionLocalEnv (LocalEnv n m1) m2 = LocalEnv n $ unionMap m1 m2 