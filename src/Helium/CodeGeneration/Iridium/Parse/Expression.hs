module Helium.CodeGeneration.Iridium.Parse.Expression where

import Helium.CodeGeneration.Iridium.Parse.Parser
import Helium.CodeGeneration.Iridium.Parse.Type
import Helium.CodeGeneration.Iridium.Data
import Helium.CodeGeneration.Iridium.Type
import Lvm.Core.Type
import Data.Maybe

pLiteral :: Parser Literal
pLiteral = do
  keyword <- pWord
  case keyword of
    "int" -> LitInt IntTypeInt <$ pWhitespace <*> pSignedInt
    "char" -> LitInt IntTypeChar <$ pWhitespace <*> pSignedInt
    "float" -> LitFloat <$> pFloatPrecision <* pWhitespace <*> pFloat
    "str" -> LitString <$ pWhitespace <*> pString
    _ -> pError "expected literal"

pFloat :: Parser Double
pFloat = do
  cMinus <- lookahead
  sign <- case cMinus of
    '-' -> do
      pChar
      return (-1)
    _ -> return 1
  int <- pUnsignedInt
  c <- lookahead
  case c of
    '.' -> do
      pChar
      decimalStr <- pManySatisfy (\c -> '0' <= c && c <= '9')
      let decimal = foldl (+) 0 $ zipWith (\c i -> fromIntegral (fromEnum c - fromEnum '0') / (10 ^ i)) decimalStr [1..]
      let value = sign * fromIntegral int + decimal
      c2 <- lookahead
      if c2 == 'e' then do
        pChar
        exp <- pSignedInt
        return $ value * 10 ^ exp
      else
        return value
    'e' -> do
      pChar
      exp <- pSignedInt
      return $ sign * fromIntegral int * 10 ^ exp
    _ -> return $ sign * fromIntegral int

pGlobal :: Parser Global
pGlobal = do
  pToken '@'
  name <- pId
  pToken ':'
  pWhitespace
  GlobalVariable name <$> pTypeAtom

pGlobalFunction :: Parser GlobalFunction
pGlobalFunction = do
  pToken '@'
  name <- pId
  pWhitespace
  pToken '['
  pWhitespace
  arity <- pUnsignedInt
  pWhitespace
  pToken ']'
  pWhitespace
  pToken ':'
  pWhitespace
  tp <- pTypeAtom
  return $ GlobalFunction name arity tp

pLocal' :: Parser Type -> Parser Local
pLocal' pTp = Local <$ pToken '%' <*> pId <* pToken ':' <* pWhitespace <*> pTp

pLocal :: QuantorNames -> Parser Local
pLocal = pLocal' . pTypeAtom'

pVariable :: QuantorNames -> Parser Variable
pVariable quantors = do
  c <- lookahead
  case c of
    '@' -> VarGlobal <$> pGlobal
    '%' -> VarLocal <$> pLocal quantors
    _ -> pError "expected variable"

pRegionVar :: Parser RegionVar
pRegionVar = do
  pToken 'ρ'
  c1 <- lookahead
  case c1 of
    '_' -> do
      pChar
      c2 <- lookahead
      case c2 of
        'g' -> RegionGlobal <$ pSymbol "global"
        'b' -> RegionBottom <$ pSymbol "bottom"
        _ -> pError "Expected global or bottom"
    _ -> RegionLocal <$> pSubscriptInt

pRegionVars :: Parser RegionVars
pRegionVars = do
  c <- lookahead
  case c of
    '(' -> RegionVarsTuple <$> pArguments pRegionVars
    _ -> RegionVarsSingle <$> pRegionVar

pAtRegion :: Parser RegionVar
pAtRegion = do
  c <- lookahead
  case c of
    '@' -> pChar *> pWhitespace *> pRegionVar
    _ -> return RegionGlobal

pAtRegions :: Parser RegionVars
pAtRegions = do
  c <- lookahead
  case c of
    '@' -> pChar *> pWhitespace *> pRegionVars
    _ -> return $ RegionVarsTuple []

pCallArguments :: QuantorNames -> Parser [Either Type Local]
pCallArguments quantors = pArguments pCallArgument
  where
    pCallArgument = do
      c <- lookahead
      if c == '{' then
        Left <$ pChar <* pWhitespace <*> pType' quantors <* pToken '}'
      else
        Right <$> pLocal quantors

pExpression :: QuantorNames -> Parser Expr
pExpression quantors = do
  keyword <- pKeyword
  case keyword of
    "literal" -> Literal <$> pLiteral
    "call" -> Call <$> pGlobalFunction <* pWhitespace <* pToken '$' <* pWhitespace <*> pAdditionalRegions <*> pCallArguments quantors <* pWhitespace <*> pAtRegions
    "eval" -> Eval <$> pVariable quantors
    "var" -> Var <$> pVariable quantors
    "instantiate" -> Instantiate <$> pLocal quantors <* pWhitespace <*> pInstantiation quantors
    -- "cast" -> Cast <$> pVariable quantors <* pWhitespace <* pSymbol "as" <* pWhitespace <*> pTypeAtom' quantors
    "castthunk" -> CastThunk <$> pLocal quantors
    "phi" -> Phi <$> pArguments (pPhiBranch quantors)
    "prim" -> PrimitiveExpr <$> pId <* pWhitespace <*> pCallArguments quantors
    "undefined" -> Undefined <$ pWhitespace <*> pTypeAtom' quantors
    "seq" -> Seq <$> pLocal quantors <* pWhitespace <* pToken ',' <* pWhitespace <*> pLocal quantors
    _ -> pError "expected expression"
  where
    pAdditionalRegions = fromMaybe (RegionVarsTuple []) <$> pMaybe (pRegionVars <* pWhitespace)

pPhiBranch :: QuantorNames -> Parser PhiBranch
pPhiBranch quantors = PhiBranch <$> pId <* pWhitespace <* pSymbol "=>" <* pWhitespace <*> pLocal quantors
