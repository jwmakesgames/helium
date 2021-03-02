module Helium.CodeGeneration.Iridium.RegionSize.Sorting
    ( sort
    ) where

import Helium.CodeGeneration.Iridium.RegionSize.Sort
import Helium.CodeGeneration.Iridium.RegionSize.Annotation
import Helium.CodeGeneration.Iridium.RegionSize.Utils
import qualified Data.Map as M

----------------------------------------------------------------
-- Sorting environment
----------------------------------------------------------------

-- | Environment for sorting
type Gamma = M.Map Int Sort

-- | Increase all env indexes by one
envInsert :: Sort -> Gamma -> Gamma
envInsert s = M.insert 0 s . envWeaken

-- | Increase all env indexes by one
envWeaken :: Gamma -> Gamma
envWeaken = M.mapKeys $ (+) 1

----------------------------------------------------------------
-- Sorting
----------------------------------------------------------------

-- | Fills in the sorts on the annotation, returns sort of full annotation
sort :: Annotation -> Sort
sort = sort' M.empty
    where sort' :: Gamma -> Annotation -> Sort 
          -- Simple cases
          sort' gamma (AVar     a) = gamma M.! a
          sort' _     (AReg     _) = SortMonoRegion
          sort' _     (AConstr  _) = SortConstr
          sort' _     (AUnit     ) = SortUnit
          
          -- Lambdas & applications
          sort' gamma (ALam   s a) = 
              let sortR =  sort' (envInsert s gamma) a
              in SortLam s $ SortTuple [sortR, SortLam SortMonoRegion SortConstr]
          sort' gamma (AApl   f x) = 
              let SortLam sortA sortR = sort' gamma f
                  sortX = sort' gamma x 
              in if sortA == sortX 
                 then sortR
                 else rsError $ "Argument has different sort than is expected.\nArgument sort: " ++ show sortX ++ "\nExpected sort:" ++ show sortA 
              
          -- Tuples & projections
          sort' gamma (ATuple  as) =
              let sortAS = map (sort' gamma) as
              in SortTuple sortAS
          sort' gamma (AProj  i t) = 
              let SortTuple ss = sort' gamma t
              in ss !! i
              
          -- Operators
          sort' gamma (AAdd   a b) = 
              let sortA = sort' gamma a
                  sortB = sort' gamma b
              in if sortA == sortB && sortA == SortConstr
                 then SortConstr
                 else rsError $ "Addition of non constraint-sort annotations: \nSort A:" ++ show sortA ++ "\nSort B:" ++ show sortB 
          sort' gamma (AJoin  a _) = sort' gamma a

          -- Quantification and instantiation
          sort' gamma (AQuant   a) = sort' (envWeaken gamma) a
          sort' gamma (AInstn a t) = sortInstantiate t $ sort' gamma a -- TODO: strengthen local indexes

          -- Lattice stuff
          sort' _     (ATop      ) = error "No sort for bottom/top"
          sort' _     (ABot      ) = error "No sort for bottom/top"
          sort' gamma (AFix   s a) =
              let sortA = sort' gamma a
              in if sortA == s
                 then s
                 else rsError $ "Fixpoint has incorrect sort: " ++ "\nNoted sort: " ++ show s ++ "\nDerived sort: " ++ show sortA   

