{-| Module      :  Unification
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable

    Perform the unification of dimension types
-}

module Helium.Helium.StaticAnalysis.Inference.DimInference.Unification where

type UnitVar  = [(Name,Int)]
type UnitCons = [(Name,Int)]
type NormUnit = (UnitVar, UnitCons)

type Unifier = M.Map Name Unit

---------------------------- Useful functions on units ------------------------

op_on_exp :: (Int -> Int) -> NormUnit -> NormUnit
op_on_exp f (uvar, ucons)
    (map (\n,int -> (n, f int) ) uvar,
     map (\n,int -> (n, f int) ) ucons)

mult :: [(Name, Int)] -> [(Name, Int)] 
-- if sorted by Name and they are because toList return an ordered List
mult (n1, int1):q1 (n2,int2):q2 =
    if n1 == n2 then
        (n1, int1 * int2):(mult q1 q2)
    else if n1 < n2 then
        (n1, int1):(mult q1 (n2,int2):q2)
    else
        (n2, int2):(mult (n1,int1):q1 q2)

multiply :: NormUnit -> NormUnit -> NormUnit
multiply (uvar1, ucons1) (uvar2, ucons2) =
    (mult uvar1 uvar2, mult ucons1 ucons2)

inverse :: NormUnit -> NormUnit
inverse (uvar, ucons) = op_on_exp (-)

power :: NormUnit -> Int -> Unit
power (uvar, ucons) exp = op_on_exp (*exp)

divide :: NormUnit -> NormUnit -> NormUnit
divide u1 u2 = 
    multiply u1 (inverse u2)

------------------------ Useful functions on substitution ---------------------

pop :: Name -> UnitVar -> (Int, UnitVar)
pop n ((name,int):uvar) =
    if name == n then
        int, uvar
    else
        let power, uvar' = pop n uvar in
            power, (name,int):uvar'

{-insert :: (Name, Int) -> Int -> [(Name, Int)] -> [(Name, Int)]
insert (name1, int1) power (name2,int2):ulist =
    if name1 == name2 then
        (name1, int1 + int2*power):ulist
    else
        (name2,int2):(insert (name1, int1) power ulist)

unify :: Unit -> Int -> Unit
unify (uvar1, ucons1) power (uvar2, ucons2) =
    (List.iter (\x -> insert x power uvar2) uvar1,
     List.iter (\x -> insert x power ucons2) ucons1)-}

substitute :: NormUnit -> Unifier -> NormUnit
substitute (uvar, ucons) subst =
    M.foldr
        (\n, u ->
            let pow, uvar' =  pop n uvar in
            -- to sort by name first: n log n then n better than n^2
            multiply (uvar', ucons) (u `power` pow)
        )
    subst

apply :: Unifier -> NormUnitType -> NormUnitType
apply _ Undimensioned = Undimensioned
apply subst (Base u)  = Base (sustitute unit subst)
apply subst (Arrow u1 u2) =
    Arrow (apply subst u1) (apply subst u2)
apply subst (Cons n lu) =
    Cons n (map (apply subst) lu)
apply subst (Tuple lu) =
    Tuple (map (apply (subst)) lu)
apply subst (List lu) =
    List (map (apply subst) lu)

-------------------------------------------------------------------------------

reduce_power :: Int -> (Name, Int) -> (Name, Int)
reduce_power x (name, int) =
    (name, int mod x) -- int - (floor int/x) * x

suppr_zero :: [Int] -> [Int]
suppr_zero [] = []
suppr_zero h:q =
    if h == 0 then suppr_zero q
    else h:q

insertion :: (Name, Int) -> UnitVar -> UnitVar -- insert in a sorted list
insertion (n,x) [] = [(n,x)]
insertion (n,x) (n',x'):q =
    if n <= n' then
        (n,x):(n',x'):q
    else (n',x'): (insertion (n,x) q)

{-
apply_substitution x_1  ([(v_1, x_1), ..., (v_m, x_m)],[(C_1, y_1), ... (C_n, y_n)])
apply to unit = v_1 ^ x_1 . ... v_m ^ x_m . C_1 ^ y_1 . ... C_n ^ y_n the substitution
 {v_1 -> v_1 . v_2 ^ -(floor x_2/ x_1) . ... . v_m ^ -(floor x_m/ x_1)
  . C_1 ^ -(floor y_1 / x_1) . ... . C_n ^( floor y_n / x_1}
-}
apply_substitution :: (Name,Int) -> NormUnit -> NormUnit
apply_substitution (n,x) (uvar, ucons) =
    let nuvar, nucons = 
        ( suppr_zero ( sortOn (abs . snd) (map (reduce_power x) uvar) ),
          suppr_zero ( sortOn (abs . snd) (map (reduce_power x) ucons) ) )
    in -- sorted regarding to the abs of the exponents, suppressing zero
    (insertion (n,x) nuvar, nucons) -- in fact, I think that (n,x) is added at the very end

compose_one :: (Name, Unit) -> Unifier -> Unifier
compose (n,u) maps =
    M.insertWith multiply n u maps


unifyOne :: NormUnit -> Either Fail Unifier -- should return an unit too...
unifyOne ([], []) = Right Substitution M.empty
unifyOne ([], _)  = Left Fail
unifyOne ([(n,x)], lcons) =
    if all (\(_,int) -> int mod x == 0) lcons then
        Right M.singleton (n,map (\(name,int) -> (name, - int/x)) lcons)
    else Left Fail
unifyOne ((n,x):q, lcons) =
    if x == 0 then
        unifyOne q lcons
    else
        let u = (n, map (\(name,int) -> (name, - floor int/x)) lcons) in
        let (uvar, ucons) = apply_substitution x (q,lcons) in
        let res = unifyOne uvar ucons in
        case res of
            Left Fail -> Left Fail
            Right s -> compose u s


------------------------------- Wider unification ----------------------------------------

{- construction of a type but base type replaced by Unit or Undimensioned -}
data UnitType a =
      Arrow (UnitType a) (UnitType a)
    | Base a 
    -- this unit could be a variable so it is already handled there
    -- but we'll have to normalize the unit before !
    | Undimensioned
    ------- Not sure about those one
    | Cons Name [(UnitType a)] 
    -- maybe string, not name - we would then have Cons "[]" = List
    | InfixConstructor (UnitType a) (UnitType a)
    | Tuple [(UnitType a)]
    | List (UnitType a) 
    | Record [(Name, (UnitType a))]


type NormUnitType = UnitType NormUnit

type UnitConstraints = [(UnitType Unit, UnitType Unit)]

-- we should not forget to label the code with dimensions?
constraint_solver ::  UnitConstraints -> Either Fail Unifier
constraint_solver lunitconst =
    let normlunitconst = map (\x,y -> (normalize x, normalize y)) lunitconst
    foldr
        (\(ut1, ut2), subst ->
            let nut1, nut2 = (apply subst ut1, apply subst ut2) in
            unify nut1 nut2 )
    M.empty
    nromlunitconst


unify :: NormUnitType -> NormUnitType -> Either Fail Unifier, NormUnitType
unfiy Undimensioned u = (Left Fail, u)
unify u Undimensioned = unify Undimensioned u
unify u1 u2 = 
    case u1, u2 of
        (Arrow a1 a2), (Arrow b1 b2) ->
            let unifier1, ut1 = unify a1 b1 in
            let na2, nb2 = apply unifier1 na2, apply unifier1 nb2 in
            let unifer2, ut2  = unify na2 nb2 in
            (compose unifier2 unifier1,
            Arrow ut1 ut2)
        (Tuple lu1), (Tuple lu2) ->
            map unify [(u1,u2) | u1 <- lu1, u2 <- lu2] -- we would in fact need a name
        (Cons n1 lu1), (Cons n2 lu2) ->
            if n1 \= n2 then Left Fail -- should have been statically checked
            else map unify [(u1,u2) | u1 <- lu1, u2 <- lu2]
        (Base u1), (Base u2) ->
            let unifier = unifyOne (divide u1 u2) in
            apply unifier u1
        _ -> Left Fail


unifyApplication :: UnitType -> [UnitType]-> Either Fail Unifier, [UnitType]
unifyApplication (Arrow ut1 lut1) ut2:lut2 =
    let unifier, nut =  unify ut1 ut2 in
    --maybe we should rather apply the unifier to lut1 and lut2; not sure
    let lunifier, nlut = unifyApplication lut1 lut2 in
    (compose unifier lunifier, nut:nlut)