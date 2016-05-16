{-# Language FlexibleContexts #-}

{- |
Module      : Language.Egison.Primitives
Copyright   : Satoshi Egi
Licence     : MIT

This module provides primitive functions in Egison.
-}

module Language.Egison.Primitives (primitiveEnv, primitiveEnvNoIO) where

import Control.Arrow
import Control.Monad.Error
import Control.Monad.Trans.Maybe
import Control.Applicative ((<$>), (<*>), (*>), (<*), pure)

import Data.IORef
import Data.Ratio
import Data.Foldable (toList)
import Text.Regex.TDFA

import System.IO
import System.Random
import System.Process

import qualified Data.Sequence as Sq

import Data.Char (ord, chr)
import qualified Data.Text as T
import Data.Text (Text)
import qualified Data.Text.IO as T

 {--  -- for 'egison-sqlite'
import qualified Database.SQLite3 as SQLite
 --}  -- for 'egison-sqlite'

import Language.Egison.Types
import Language.Egison.Parser
import Language.Egison.Core

primitiveEnv :: IO Env
primitiveEnv = do
  let ops = map (\(name, fn) -> (name, PrimitiveFunc name fn)) (primitives ++ ioPrimitives)
  bindings <- forM (constants ++ ops) $ \(name, op) -> do
    ref <- newIORef . WHNF $ Value op
    return (name, ref)
  return $ extendEnv nullEnv bindings

primitiveEnvNoIO :: IO Env
primitiveEnvNoIO = do
  let ops = map (\(name, fn) -> (name, PrimitiveFunc name fn)) primitives
  bindings <- forM (constants ++ ops) $ \(name, op) -> do
    ref <- newIORef . WHNF $ Value op
    return (name, ref)
  return $ extendEnv nullEnv bindings

{-# INLINE noArg #-}
noArg :: EgisonM EgisonValue -> PrimitiveFunc
noArg f = \args -> do
  args' <- tupleToList args
  case args' of 
    [] -> f >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 0 $ length args'

{-# INLINE oneArg #-}
oneArg :: (EgisonValue -> EgisonM EgisonValue) -> PrimitiveFunc
oneArg f = \args -> do
  args' <- evalWHNF args
  f args' >>= return . Value

{-# INLINE twoArgs #-}
twoArgs :: (EgisonValue -> EgisonValue -> EgisonM EgisonValue) -> PrimitiveFunc
twoArgs f = \args -> do
  args' <- tupleToList args
  case args' of 
    [val, val'] -> f val val' >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 2 $ length args'

{-# INLINE threeArgs #-}
threeArgs :: (EgisonValue -> EgisonValue -> EgisonValue -> EgisonM EgisonValue) -> PrimitiveFunc
threeArgs f = \args -> do
  args' <- tupleToList args
  case args' of 
    [val, val', val''] -> f val val' val'' >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 3 $ length args'

--
-- Constants
--

constants :: [(String, EgisonValue)]
constants = [
              ("f.pi", Float 3.141592653589793 0)
             ,("f.e" , Float 2.718281828459045 0)
              ]

--
-- Primitives
--

primitives :: [(String, PrimitiveFunc)]
primitives = [ ("b.+", plus)
             , ("b.-", minus)
             , ("b.*", multiply)
             , ("b./", divide)
             , ("b.+'", plus)
             , ("b.-'", minus)
             , ("b.*'", multiply)
             , ("b./'", divide)
             , ("numerator", numerator')
             , ("denominator", denominator')
             , ("from-math-expr", fromScalarData)
             , ("to-math-expr", toScalarData)
             , ("to-math-expr'", toScalarData)

             , ("modulo",    integerBinaryOp mod)
             , ("quotient",   integerBinaryOp quot)
             , ("remainder", integerBinaryOp rem)
             , ("abs", rationalUnaryOp abs)
             , ("neg", rationalUnaryOp negate)
               
             , ("eq?",  eq)
             , ("lt?",  lt)
             , ("lte?", lte)
             , ("gt?",  gt)
             , ("gte?", gte)
               
             , ("round",    floatToIntegerOp round)
             , ("floor",    floatToIntegerOp floor)
             , ("ceiling",  floatToIntegerOp ceiling)
             , ("truncate", truncate')
             , ("real-part", realPart)
             , ("imaginary-part", imaginaryPart)
               
             , ("b.sqrt", floatUnaryOp sqrt)
             , ("b.sqrt'", floatUnaryOp sqrt)
             , ("b.exp", floatUnaryOp exp)
             , ("b.log", floatUnaryOp log)
             , ("b.sin", floatUnaryOp sin)
             , ("b.cos", floatUnaryOp cos)
             , ("b.tan", floatUnaryOp tan)
             , ("b.asin", floatUnaryOp asin)
             , ("b.acos", floatUnaryOp acos)
             , ("b.atan", floatUnaryOp atan)
             , ("b.sinh", floatUnaryOp sinh)
             , ("b.cosh", floatUnaryOp cosh)
             , ("b.tanh", floatUnaryOp tanh)
             , ("b.asinh", floatUnaryOp asinh)
             , ("b.acosh", floatUnaryOp acosh)
             , ("b.atanh", floatUnaryOp atanh)

             , ("b..", tensorProd)
             , ("b..'", tensorProd)
             , ("tensor-index", tensorIndex)
             , ("tensor-size", tensorSize)
             , ("tensor-to-list", tensorToList)

             , ("itof", integerToFloat)
             , ("rtof", rationalToFloat)
             , ("ctoi", charToInteger)
             , ("itoc", integerToChar)

             , ("pack", pack)
             , ("unpack", unpack)
             , ("uncons-string", unconsString)
             , ("length-string", lengthString)
             , ("append-string", appendString)
             , ("split-string", splitString)
             , ("regex", regexString)
             , ("regex-cg", regexStringCaptureGroup)

             , ("add-prime", addPrime)
             , ("add-subscript", addSubscript)
             , ("add-superscript", addSuperscript)

             , ("read-process", readProcess')
               
             , ("read", read')
             , ("read-tsv", readTSV)
             , ("show", show')
             , ("show-tsv", showTSV')

             , ("empty?", isEmpty')
             , ("uncons", uncons')
             , ("unsnoc", unsnoc')

             , ("bool?", isBool')
             , ("integer?", isInteger')
             , ("rational?", isRational')
             , ("scalar?", isScalar')
             , ("float?", isFloat')
             , ("char?", isChar')
             , ("string?", isString')
             , ("collection?", isCollection')
             , ("array?", isArray')
             , ("hash?", isHash')
             , ("tensor?", isTensor')
             , ("tensor-with-index?", isTensorWithIndex')

             , ("assert", assert)
             , ("assert-equal", assertEqual)
             ]

rationalUnaryOp :: (Rational -> Rational) -> PrimitiveFunc
rationalUnaryOp op = oneArg $ \val -> do
  r <- fromEgison val
  let r' =  op r
  return $ toEgison r'
  
rationalBinaryOp :: (Rational -> Rational -> Rational) -> PrimitiveFunc
rationalBinaryOp op = twoArgs $ \val val' -> do
  r <- fromEgison val :: EgisonM Rational
  r' <- fromEgison val' :: EgisonM Rational
  let r'' = (op r r'')
  return $ toEgison r''

rationalBinaryPred :: (Rational -> Rational -> Bool) -> PrimitiveFunc
rationalBinaryPred pred = twoArgs $ \val val' -> do
  r <- fromEgison val
  r' <- fromEgison val'
  return $ Bool $ pred r r'

integerBinaryOp :: (Integer -> Integer -> Integer) -> PrimitiveFunc
integerBinaryOp op = twoArgs $ \val val' -> do
  i <- fromEgison val
  i' <- fromEgison val'
  return $ toEgison (op i i')

integerBinaryPred :: (Integer -> Integer -> Bool) -> PrimitiveFunc
integerBinaryPred pred = twoArgs $ \val val' -> do
  i <- fromEgison val
  i' <- fromEgison val'
  return $ Bool $ pred i i'

floatUnaryOp :: (Double -> Double) -> PrimitiveFunc
floatUnaryOp op = oneArg $ \val -> do
  case val of
    (Float f 0) -> return $ Float (op f) 0
    _ -> throwError $ TypeMismatch "float" (Value val)

floatBinaryOp :: (Double -> Double -> Double) -> PrimitiveFunc
floatBinaryOp op = twoArgs $ \val val' -> do
  case (val, val') of
    ((Float f 0), (Float f' 0)) -> return $ Float (op f f') 0
    _ -> throwError $ TypeMismatch "float" (Value val)

floatBinaryPred :: (Double -> Double -> Bool) -> PrimitiveFunc
floatBinaryPred pred = twoArgs $ \val val' -> do
  f <- fromEgison val
  f' <- fromEgison val'
  return $ Bool $ pred f f'

--
-- Arith
--

numberUnaryOp :: (ScalarData -> ScalarData) -> (EgisonValue -> EgisonValue) -> PrimitiveFunc
numberUnaryOp mOp fOp arg = do
  arg' <- tupleToList arg
  case arg' of 
    [val] -> numberUnaryOp' val >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 1 $ length arg'
 where
  numberUnaryOp' f@(Float _ _)  = return $ fOp f
  numberUnaryOp' (ScalarData m) = (return . ScalarData . mathNormalize') (mOp m)
  numberUnaryOp' val            = throwError $ TypeMismatch "number" (Value val)

numberBinaryOp :: (ScalarData -> ScalarData -> ScalarData) -> (EgisonValue -> EgisonValue -> EgisonValue) -> PrimitiveFunc
numberBinaryOp mOp fOp args = do
  args' <- tupleToList args
  case args' of 
    [val, val'] -> numberBinaryOp' val val' >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 2 $ length args'
 where
  numberBinaryOp' f@(Float _ _)   f'@(Float _ _)  = return $ fOp f f'
  numberBinaryOp' val             (Float x' y')   = numberBinaryOp' (numberToFloat' val) (Float x' y')
  numberBinaryOp' (Float x y)     val'            = numberBinaryOp' (Float x y) (numberToFloat' val')
  numberBinaryOp' (ScalarData m1) (ScalarData m2) = (return . ScalarData . mathNormalize') (mOp m1 m2)
  numberBinaryOp' (ScalarData _)  val'            = throwError $ TypeMismatch "number" (Value val')
  numberBinaryOp' val             _               = throwError $ TypeMismatch "number" (Value val)

plus :: PrimitiveFunc
plus = numberBinaryOp mathPlus (\(Float x y) (Float x' y') -> Float (x + x')  (y + y'))

minus :: PrimitiveFunc
minus = numberBinaryOp (\m1 m2 -> mathPlus m1 (mathNegate m2)) (\(Float x y) (Float x' y') -> Float (x - x')  (y - y'))

multiply :: PrimitiveFunc
multiply = numberBinaryOp mathMult (\(Float x y) (Float x' y') -> Float (x * x' - y * y')  (x * y' + x' * y))

divide :: PrimitiveFunc
divide = numberBinaryOp (\m1 (Div p1 p2) -> mathMult m1 (Div p2 p1)) (\(Float x y) (Float x' y') -> Float ((x * x' + y * y') / (x' * x' + y' * y')) ((y * x' - x * y') / (x' * x' + y' * y')))

numerator' :: PrimitiveFunc
numerator' =  oneArg $ numerator''
 where
  numerator'' (ScalarData m) = return $ ScalarData (mathNumerator m)
  numerator'' val = throwError $ TypeMismatch "rational" (Value val)

denominator' :: PrimitiveFunc
denominator' =  oneArg $ denominator''
 where
  denominator'' (ScalarData m) = return $ ScalarData (mathDenominator m)
  denominator'' val = throwError $ TypeMismatch "rational" (Value val)

fromScalarData :: PrimitiveFunc
fromScalarData = oneArg $ fromScalarData'
 where
  fromScalarData' (ScalarData m) = return $ mathExprToEgison m
  fromScalarData' val = throwError $ TypeMismatch "number" (Value val)

toScalarData :: PrimitiveFunc
toScalarData = oneArg $ toScalarData'
 where
  toScalarData' val = egisonToScalarData val >>= return . ScalarData . mathNormalize'

--
-- Pred
--
eq :: PrimitiveFunc
eq = twoArgs $ \val val' ->
  return $ Bool $ val == val'

lt :: PrimitiveFunc
lt = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarData _) n@(ScalarData _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (<) r r'
  numberBinaryPred' (Float f 0)  (Float f' 0)  = return $ Bool $ (<) f f'
  numberBinaryPred' (ScalarData _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)  val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val          _             = throwError $ TypeMismatch "number" (Value val)
  
lte :: PrimitiveFunc
lte = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarData _) n@(ScalarData _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (<=) r r'
  numberBinaryPred' (Float f 0)  (Float f' 0)  = return $ Bool $ (<=) f f'
  numberBinaryPred' (ScalarData _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)  val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val          _             = throwError $ TypeMismatch "number" (Value val)
  
gt :: PrimitiveFunc
gt = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarData _) n@(ScalarData _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (>) r r'
  numberBinaryPred' (Float f 0)  (Float f' 0)  = return $ Bool $ (>) f f'
  numberBinaryPred' (ScalarData _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)  val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val          _             = throwError $ TypeMismatch "number" (Value val)
  
gte :: PrimitiveFunc
gte = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarData _) n@(ScalarData _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (>=) r r'
  numberBinaryPred' (Float f 0)    (Float f' 0)  = return $ Bool $ (>=) f f'
  numberBinaryPred' (ScalarData _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)    val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val            _             = throwError $ TypeMismatch "number" (Value val)
  
truncate' :: PrimitiveFunc
truncate' = oneArg $ \val -> numberUnaryOp' val
 where
  numberUnaryOp' (ScalarData (Div (Plus []) _)) = return $ toEgison (0 :: Integer)
  numberUnaryOp' (ScalarData (Div (Plus [(Term x [])]) (Plus [(Term y [])]))) = return $ toEgison (quot x y)
  numberUnaryOp' (Float x _)           = return $ toEgison ((truncate x) :: Integer)
  numberUnaryOp' val                   = throwError $ TypeMismatch "ratinal or float" (Value val)

realPart :: PrimitiveFunc
realPart =  oneArg $ realPart'
 where
  realPart' (Float x y) = return $ Float x 0
  realPart' val = throwError $ TypeMismatch "float" (Value val)

imaginaryPart :: PrimitiveFunc
imaginaryPart =  oneArg $ imaginaryPart'
 where
  imaginaryPart' (Float _ y) = return $ Float y 0
  imaginaryPart' val = throwError $ TypeMismatch "float" (Value val)

--
-- Tensor
--

tensorProd :: PrimitiveFunc
tensorProd = twoArgs $ tensorProd'
 where
  tensorProd' (TensorData (TData (Tensor ns1 xs1) (Just ms1)))
              (TensorData (TData (Tensor ns2 xs2) (Just ms2))) = do
    ret <- tContract (TData (Tensor (ns1 ++ ns2) (map (\is -> let is1 = take (length ns1) is in
                                                              let is2 = take (length ns2) (drop (length ns1) is) in
                                                                (mathMult (tref' is1 (Tensor ns1 xs1)) (tref' is2 (Tensor ns2 xs2)))
                                                       ) (tensorIndices (ns1 ++ ns2)))) (Just (ms1 ++ ms2)))
    return ret
  tensorProd' val1 val2 = throwError $ TypeMismatch "tensor data with index" (Value (Tuple [val1, val2]))

tensorIndex :: PrimitiveFunc
tensorIndex = oneArg $ tensorIndex'
 where
--  tensorIndex' (TensorData (TData (Tensor _ _) (Just ms))) = return . Collection . Sq.fromList $ map ScalarData ms
  tensorIndex' val = throwError $ TypeMismatch "tensor with index" (Value val)

tensorSize :: PrimitiveFunc
tensorSize = oneArg $ tensorSize'
 where
  tensorSize' (TensorData (TData (Tensor ns _) _)) = return . Collection . Sq.fromList $ map toEgison ns
  tensorSize' val = throwError $ TypeMismatch "tensor data" (Value val)

tensorToList :: PrimitiveFunc
tensorToList = oneArg $ tensorToList'
 where
  tensorToList' (TensorData (TData (Tensor _ xs) _)) = return . Collection . Sq.fromList $ map ScalarData xs
  tensorToList' val = throwError $ TypeMismatch "tensor data" (Value val)

--
-- Transform
--
numberToFloat' :: EgisonValue -> EgisonValue
numberToFloat' (ScalarData (Div (Plus []) _)) = Float 0 0
numberToFloat' (ScalarData (Div (Plus [(Term x [])]) (Plus [(Term y [])]))) = Float (fromRational (x % y)) 0

integerToFloat :: PrimitiveFunc
integerToFloat = rationalToFloat

rationalToFloat :: PrimitiveFunc
rationalToFloat = oneArg $ \val ->
  case val of
    (ScalarData (Div (Plus []) _)) -> return $ numberToFloat' val
    (ScalarData (Div (Plus [(Term _ [])]) (Plus [(Term _ [])]))) -> return $ numberToFloat' val
    _ -> throwError $ TypeMismatch "integer or rational number" (Value val)

charToInteger :: PrimitiveFunc
charToInteger = oneArg $ \val -> do
  case val of
    Char c -> do
      let i = fromIntegral $ ord c :: Integer
      return $ toEgison i
    _ -> throwError $ TypeMismatch "character" (Value val)

integerToChar :: PrimitiveFunc
integerToChar = oneArg $ \val -> do
  case val of
    (ScalarData _) -> do
       i <- fromEgison val :: EgisonM Integer
       return $ Char $ chr $ fromIntegral i
    _ -> throwError $ TypeMismatch "integer" (Value val)

floatToIntegerOp :: (Double -> Integer) -> PrimitiveFunc
floatToIntegerOp op = oneArg $ \val -> do
  f <- fromEgison val
  return $ toEgison (op f)

--
-- String
--
pack :: PrimitiveFunc
pack = oneArg $ \val -> do
  str <- packStringValue val
  return $ String str

unpack :: PrimitiveFunc
unpack = oneArg $ \val -> do
  case val of
    String str -> return $ toEgison (T.unpack str)
    _ -> throwError $ TypeMismatch "string" (Value val)

unconsString :: PrimitiveFunc
unconsString = oneArg $ \val -> do
  case val of
    String str -> case T.uncons str of
                    Just (c, rest) ->  return $ Tuple [Char c, String rest]
                    Nothing -> throwError $ Default "Tried to unsnoc empty string"
    _ -> throwError $ TypeMismatch "string" (Value val)

lengthString :: PrimitiveFunc
lengthString = oneArg $ \val -> do
  case val of
    String str -> return . (\x -> toEgison x) . toInteger $ T.length str
    _ -> throwError $ TypeMismatch "string" (Value val)

appendString :: PrimitiveFunc
appendString = twoArgs $ \val1 val2 -> do
  case (val1, val2) of
    (String str1, String str2) -> return . String $ T.append str1 str2
    (String _, _) -> throwError $ TypeMismatch "string" (Value val2)
    (_, _) -> throwError $ TypeMismatch "string" (Value val1)

splitString :: PrimitiveFunc
splitString = twoArgs $ \pat src -> do
  case (pat, src) of
    (String patStr, String srcStr) -> return . Collection . Sq.fromList $ map String $ T.splitOn patStr srcStr
    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

regexString :: PrimitiveFunc
regexString = twoArgs $ \pat src -> do
  case (pat, src) of
    (String patStr, String srcStr) -> do
      let (a, b, c) = (((T.unpack srcStr) =~ (T.unpack patStr)) :: (String, String, String))
      if b == ""
        then return . Collection . Sq.fromList $ []
        else return . Collection . Sq.fromList $ [Tuple [String $ T.pack a, String $ T.pack b, String $ T.pack c]]
    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

regexStringCaptureGroup :: PrimitiveFunc
regexStringCaptureGroup = twoArgs $ \pat src -> do
  case (pat, src) of
    (String patStr, String srcStr) -> do
      let ret = (((T.unpack srcStr) =~ (T.unpack patStr)) :: [[String]])
      case ret of 
        [] -> return . Collection . Sq.fromList $ []
        ((x:xs):_) -> do let (a, c) = T.breakOn (T.pack x) srcStr
                         return . Collection . Sq.fromList $ [Tuple [String a, Collection (Sq.fromList (map (String . T.pack) xs)), String (T.drop (length x) c)]]
    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

--regexStringMatch :: PrimitiveFunc
--regexStringMatch = twoArgs $ \pat src -> do
--  case (pat, src) of
--    (String patStr, String srcStr) -> return . Bool $ (((T.unpack srcStr) =~ (T.unpack patStr)) :: Bool)
--    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
--    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

addPrime :: PrimitiveFunc
addPrime = oneArg $ \sym -> do
  case sym of
    ScalarData (Div (Plus [(Term 1 [(Symbol name is, 1)])]) (Plus [(Term 1 [])])) -> return (ScalarData (Div (Plus [(Term 1 [(Symbol (name ++ "'") is, 1)])]) (Plus [(Term 1 [])])))
    _ ->  throwError $ TypeMismatch "symbol" (Value sym)

addSubscript :: PrimitiveFunc
addSubscript = twoArgs $ \fn sub -> do
  case (fn, sub) of
    (ScalarData (Div (Plus [(Term 1 [(Symbol name is, 1)])]) (Plus [(Term 1 [])])),
     ScalarData s@(Div (Plus [(Term 1 [(Symbol _ [], 1)])]) (Plus [(Term 1 [])]))) -> return (ScalarData (Div (Plus [(Term 1 [(Symbol name (is ++ [Subscript s]), 1)])]) (Plus [(Term 1 [])])))
    (ScalarData (Div (Plus [(Term 1 [(Symbol name is, 1)])]) (Plus [(Term 1 [])])),
     _) -> throwError $ TypeMismatch "symbol" (Value sub)
    _ ->  throwError $ TypeMismatch "symbol" (Value fn)

addSuperscript :: PrimitiveFunc
addSuperscript = twoArgs $ \fn sub -> do
  case (fn, sub) of
    (ScalarData (Div (Plus [(Term 1 [(Symbol name is, 1)])]) (Plus [(Term 1 [])])),
     ScalarData s@(Div (Plus [(Term 1 [(Symbol _ [], 1)])]) (Plus [(Term 1 [])]))) -> return (ScalarData (Div (Plus [(Term 1 [(Symbol name (is ++ [Superscript s]), 1)])]) (Plus [(Term 1 [])])))
    (ScalarData (Div (Plus [(Term 1 [(Symbol name is, 1)])]) (Plus [(Term 1 [])])),
     _) -> throwError $ TypeMismatch "symbol" (Value sub)
    _ ->  throwError $ TypeMismatch "symbol" (Value fn)

readProcess' :: PrimitiveFunc
readProcess' = threeArgs $ \cmd args input -> do
  case (cmd, args, input) of
    (String cmdStr, Collection argStrs, String inputStr) -> do
      outputStr <- liftIO $ readProcess (T.unpack cmdStr) (map (\arg -> case arg of
                                                                          String argStr -> T.unpack argStr)
                                                                (toList argStrs)) (T.unpack inputStr)
      return (String (T.pack outputStr))
    (_, _, _) -> throwError $ TypeMismatch "(string, collection, string)" (Value (Tuple [cmd, args, input]))

read' :: PrimitiveFunc
read'= oneArg $ \val -> fromEgison val >>= readExpr . T.unpack >>= evalExprDeep nullEnv

readTSV :: PrimitiveFunc
readTSV= oneArg $ \val -> do rets <- fromEgison val >>= readExprs . T.unpack >>= mapM (evalExprDeep nullEnv)
                             case rets of
                               [ret] -> return ret
                               _ -> return (Tuple rets)

show' :: PrimitiveFunc
show'= oneArg $ \val -> return $ toEgison $ T.pack $ show val

showTSV' :: PrimitiveFunc
showTSV'= oneArg $ \val -> return $ toEgison $ T.pack $ showTSV val

--
-- Collection
--
isEmpty' :: PrimitiveFunc
isEmpty' whnf = do
  b <- isEmptyCollection whnf
  if b
    then return $ Value $ Bool True
    else return $ Value $ Bool False

uncons' :: PrimitiveFunc
uncons' whnf = do
  mRet <- runMaybeT (unconsCollection whnf)
  case mRet of
    Just (carObjRef, cdrObjRef) -> return $ Intermediate $ ITuple [carObjRef, cdrObjRef]
    Nothing -> throwError $ Default $ "cannot uncons collection"

unsnoc' :: PrimitiveFunc
unsnoc' whnf = do
  mRet <- runMaybeT (unsnocCollection whnf)
  case mRet of
    Just (racObjRef, rdcObjRef) -> return $ Intermediate $ ITuple [racObjRef, rdcObjRef]
    Nothing -> throwError $ Default $ "cannot unsnoc collection"

-- Test

assert ::  PrimitiveFunc
assert = twoArgs $ \label test -> do
  test <- fromEgison test
  if test
    then return $ Bool True
    else throwError $ Assertion $ show label

assertEqual :: PrimitiveFunc
assertEqual = threeArgs $ \label actual expected -> do
  if actual == expected
    then return $ Bool True
    else throwError $ Assertion $ show label ++ "\n expected: " ++ show expected ++
                                  "\n but found: " ++ show actual

--
-- IO Primitives
--

ioPrimitives :: [(String, PrimitiveFunc)]
ioPrimitives = [
                 ("return", return')
               , ("open-input-file", makePort ReadMode)
               , ("open-output-file", makePort WriteMode)
               , ("close-input-port", closePort)
               , ("close-output-port", closePort)
               , ("read-char", readChar)
               , ("read-line", readLine)
               , ("write-char", writeChar)
               , ("write", writeString)
                 
               , ("read-char-from-port", readCharFromPort)
               , ("read-line-from-port", readLineFromPort)
               , ("write-char-to-port", writeCharToPort)
               , ("write-to-port", writeStringToPort)
                 
               , ("eof?", isEOFStdin)
               , ("flush", flushStdout)
               , ("eof-port?", isEOFPort)
               , ("flush-port", flushPort)
               , ("read-file", readFile')
                 
               , ("rand", randRange)
--               , ("sqlite", sqlite)
               ]

makeIO :: EgisonM EgisonValue -> EgisonValue
makeIO m = IOFunc $ liftM (Value . Tuple . (World :) . (:[])) m

makeIO' :: EgisonM () -> EgisonValue
makeIO' m = IOFunc $ m >> return (Value $ Tuple [World, Tuple []])

return' :: PrimitiveFunc
return' = oneArg $ \val -> return $ makeIO $ return val

makePort :: IOMode -> PrimitiveFunc
makePort mode = oneArg $ \val -> do
  filename <- fromEgison val
  port <- liftIO $ openFile (T.unpack filename) mode
  return $ makeIO $ return (Port port)

closePort :: PrimitiveFunc
closePort = oneArg $ \val -> do
  port <- fromEgison val
  return $ makeIO' $ liftIO $ hClose port

writeChar :: PrimitiveFunc
writeChar = oneArg $ \val -> do
  c <- fromEgison val
  return $ makeIO' $ liftIO $ putChar c

writeCharToPort :: PrimitiveFunc
writeCharToPort = twoArgs $ \val val' -> do
  port <- fromEgison val
  c <- fromEgison val'
  return $ makeIO' $ liftIO $ hPutChar port c

writeString :: PrimitiveFunc
writeString = oneArg $ \val -> do
  s <- fromEgison val
  return $ makeIO' $ liftIO $ T.putStr s
  
writeStringToPort :: PrimitiveFunc
writeStringToPort = twoArgs $ \val val' -> do
  port <- fromEgison val
  s <- fromEgison val'
  return $ makeIO' $ liftIO $ T.hPutStr port s

flushStdout :: PrimitiveFunc
flushStdout = noArg $ return $ makeIO' $ liftIO $ hFlush stdout

flushPort :: PrimitiveFunc
flushPort = oneArg $ \val -> do
  port <- fromEgison val
  return $ makeIO' $ liftIO $ hFlush port

readChar :: PrimitiveFunc
readChar = noArg $ return $ makeIO $ liftIO $ liftM Char getChar

readCharFromPort :: PrimitiveFunc
readCharFromPort = oneArg $ \val -> do
  port <- fromEgison val
  c <- liftIO $ hGetChar port
  return $ makeIO $ return (Char c)

readLine :: PrimitiveFunc
readLine = noArg $ return $ makeIO $ liftIO $ liftM toEgison T.getLine

readLineFromPort :: PrimitiveFunc
readLineFromPort = oneArg $ \val -> do
  port <- fromEgison val
  s <- liftIO $ T.hGetLine port
  return $ makeIO $ return $ toEgison s

readFile' :: PrimitiveFunc
readFile' =  oneArg $ \val -> do
  filename <- fromEgison val
  s <- liftIO $ T.readFile $ T.unpack filename
  return $ makeIO $ return $ toEgison s
  
isEOFStdin :: PrimitiveFunc
isEOFStdin = noArg $ return $ makeIO $ liftIO $ liftM Bool isEOF

isEOFPort :: PrimitiveFunc
isEOFPort = oneArg $ \val -> do
  port <- fromEgison val
  b <- liftIO $ hIsEOF port
  return $ makeIO $ return (Bool b)

randRange :: PrimitiveFunc
randRange = twoArgs $ \val val' -> do
  i <- fromEgison val :: EgisonM Integer
  i' <- fromEgison val' :: EgisonM Integer
  n <- liftIO $ getStdRandom $ randomR (i, i')
  return $ makeIO $ return $ toEgison n

 {-- -- for 'egison-sqlite'
sqlite :: PrimitiveFunc
sqlite  = twoArgs $ \val val' -> do
  dbName <- fromEgison val
  qStr <- fromEgison val'
  ret <- liftIO $ query' (T.pack dbName) $ T.pack qStr
  return $ makeIO $ return $ Collection $ Sq.fromList $ map (\r -> Tuple (map toEgison r)) ret
 where
  query' :: T.Text -> T.Text -> IO [[String]]
  query' dbName q = do
    db <- SQLite.open dbName
    rowsRef <- newIORef []
    SQLite.execWithCallback db q (\_ _ mcs -> do
                                    row <- forM mcs (\mcol -> case mcol of
                                                              Just col ->  return $ T.unpack col
                                                              Nothing -> return "null")
                                    rows <- readIORef rowsRef
                                    writeIORef rowsRef (row:rows))
    SQLite.close db
    ret <- readIORef rowsRef
    return $ reverse ret
 --} -- for 'egison-sqlite'
