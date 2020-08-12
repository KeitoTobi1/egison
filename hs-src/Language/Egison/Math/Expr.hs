{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms       #-}
{-# LANGUAGE QuasiQuotes           #-}

{- |
Module      : Language.Egison.MathExpr
Licence     : MIT

This module contains functions for mathematical expressions.
-}

module Language.Egison.Math.Expr
    ( ScalarData (..)
    , PolyExpr (..)
    , TermExpr (..)
    , Monomial
    , SymbolExpr (..)
    , Printable (..)
    , pattern ZeroExpr
    , pattern SingleSymbol
    , pattern SingleTerm
    , ScalarM (..)
    , TermM (..)
    , SymbolM (..)
    , div
    , divM
    , term
    , termM
    , symbol
    , symbolM
    , apply
    , applyM
    , quote
    , negQuote
    , negQuoteM
    , equalMonomial
    , equalMonomialM
    , zero
    , zeroM
    , singleSymbol
    , singleSymbolM
    , singleTerm
    , singleTermM
    , mathNegate
    ) where

import           Prelude                   hiding (div, foldr, mappend, mconcat)
import           Data.List                 (intercalate)

import           Control.Monad             ( MonadPlus(..) )
import           Control.Egison

import           Language.Egison.AST

--
-- Data
--


data ScalarData
  = Div PolyExpr PolyExpr
 deriving (Eq)

newtype PolyExpr
  = Plus [TermExpr]

data TermExpr
  = Term Integer Monomial

-- We choose the definition 'monomials' without its coefficients.
-- ex. 2 x^2 y^3 is *not* a monomial. x^2 t^3 is a monomial.
type Monomial = [(SymbolExpr, Integer)]

data SymbolExpr
  = Symbol Id String [Index ScalarData]
  | Apply ScalarData [ScalarData]
  | Quote ScalarData
  | FunctionData ScalarData [ScalarData] [ScalarData] [Index ScalarData] -- fnname argnames args indices
 deriving (Eq)

type Id = String

-- Matchers

data ScalarM = ScalarM
instance Matcher ScalarM ScalarData

data TermM = TermM
instance Matcher TermM TermExpr

data SymbolM = SymbolM
instance Matcher SymbolM SymbolExpr

div :: Pattern (PP [TermExpr], PP [TermExpr]) ScalarM ScalarData ([TermExpr], [TermExpr])
div _ _ (Div (Plus ts1) (Plus ts2)) = pure (ts1, ts2)
divM :: ScalarM -> ScalarData -> (Multiset TermM, Multiset TermM)
divM ScalarM _ = (Multiset TermM, Multiset TermM)

term :: Pattern (PP Integer, PP Monomial) TermM TermExpr (Integer, Monomial)
term _ _ (Term a mono) = pure (a, mono)
termM :: TermM -> TermExpr -> (Eql, Multiset (Pair SymbolM Eql))
termM TermM _ = (Eql, Multiset (Pair SymbolM Eql))

symbol :: Pattern (PP String) SymbolM SymbolExpr String
symbol _ _ (Symbol _ name _) = pure name
symbol _ _ _                 = mzero
symbolM :: SymbolM -> p -> Eql
symbolM SymbolM _ = Eql

apply :: Pattern (PP String, PP [ScalarData]) SymbolM SymbolExpr (String, [ScalarData])
apply _ _ (Apply (SingleSymbol (Symbol _ fn _)) args) = pure (fn, args)
apply _ _ _                                           = mzero
applyM :: SymbolM -> p -> (Eql, List ScalarM)
applyM SymbolM _ = (Eql, List ScalarM)

quote :: Pattern (PP ScalarData) SymbolM SymbolExpr ScalarData
quote _ _ (Quote m) = pure m
quote _ _ _         = mzero

negQuote :: Pattern (PP ScalarData) SymbolM SymbolExpr ScalarData
negQuote _ _ (Quote m) = pure (mathNegate m)
negQuote _ _ _         = mzero
negQuoteM :: SymbolM -> p -> ScalarM
negQuoteM SymbolM _ = ScalarM

equalMonomial :: Pattern (PP Integer, PP Monomial) (Multiset (Pair SymbolM Eql)) Monomial (Integer, Monomial)
equalMonomial (_, VP xs) _ ys = case isEqualMonomial xs ys of
                                  Just sgn -> pure (sgn, xs)
                                  Nothing  -> mzero
equalMonomial _ _ _ = mzero
equalMonomialM :: Multiset (Pair SymbolM Eql) -> p -> (Eql, Multiset (Pair SymbolM Eql))
equalMonomialM (Multiset (Pair SymbolM Eql)) _ = (Eql, Multiset (Pair SymbolM Eql))

zero :: Pattern () ScalarM ScalarData ()
zero _ _ (Div (Plus []) _) = pure ()
zero _ _ _                 = mzero
zeroM :: ScalarM -> p -> ()
zeroM ScalarM _ = ()

singleSymbol :: Pattern (PP SymbolExpr) ScalarM ScalarData SymbolExpr
singleSymbol _ _ (Div (Plus [Term 1 [(sym, 1)]]) (Plus [Term 1 []])) = pure sym
singleSymbol _ _ _                                                   = mzero
singleSymbolM :: ScalarM -> p -> SymbolM
singleSymbolM ScalarM _ = SymbolM

singleTerm :: Pattern (PP Integer, PP Monomial) ScalarM ScalarData (Integer, Monomial)
singleTerm _ _ (Div (Plus [Term coeff mono]) (Plus [Term 1 []])) = pure (coeff, mono)
singleTerm _ _ _                                                 = mzero
singleTermM :: ScalarM -> p -> (Eql, Multiset (Pair SymbolM Eql))
singleTermM ScalarM _ = (Eql, Multiset (Pair SymbolM Eql))


instance ValuePattern ScalarM ScalarData where
  value e () ScalarM v = if e == v then pure () else mzero

instance ValuePattern SymbolM SymbolExpr where
  value e () SymbolM v = if e == v then pure () else mzero


pattern ZeroExpr :: ScalarData
pattern ZeroExpr = (Div (Plus []) (Plus [Term 1 []]))

pattern SingleSymbol :: SymbolExpr -> ScalarData
pattern SingleSymbol sym = Div (Plus [Term 1 [(sym, 1)]]) (Plus [Term 1 []])

-- Product of a coefficient and a monomial
pattern SingleTerm :: Integer -> Monomial -> ScalarData
pattern SingleTerm coeff mono = Div (Plus [Term coeff mono]) (Plus [Term 1 []])

instance Eq PolyExpr where
  Plus xs == Plus ys =
    match dfs ys (Multiset Eql)
      [ [mc| #xs -> True |]
      , [mc| _   -> False |] ]

instance Eq TermExpr where
  Term a xs == Term b ys
    | a == b    = isEqualMonomial xs ys == Just 1
    | a == -b   = isEqualMonomial xs ys == Just (-1)
    | otherwise = False

isEqualMonomial :: Monomial -> Monomial -> Maybe Integer
isEqualMonomial xs ys =
  match dfs (xs, ys) (Pair (Multiset (Pair SymbolM Eql)) (Multiset (Pair SymbolM Eql)))
    [ [mc| ((quote $s, $n) : $xss, (negQuote #s, #n) : $yss) ->
             case isEqualMonomial xss yss of
               Nothing -> Nothing
               Just sgn -> return (if even n then sgn else - sgn) |]
    , [mc| (($x, $n) : $xss, (#x, #n) : $yss) -> isEqualMonomial xss yss |]
    , [mc| ([], []) -> return 1 |]
    , [mc| _ -> Nothing |]
    ]

--
--  Arithmetic operations
--

mathNegate :: ScalarData -> ScalarData
mathNegate (Div m n) = Div (mathNegate' m) n
  where
    mathNegate' (Plus ts) = Plus (map (\(Term a xs) -> Term (-a) xs) ts)

--
-- Pretty printing
--

class Printable a where
  isAtom :: a -> Bool
  pretty :: a -> String

pretty' :: Printable a => a -> String
pretty' e | isAtom e = pretty e
pretty' e            = "(" ++ pretty e ++ ")"

instance Printable ScalarData where
  isAtom (Div p (Plus [Term 1 []])) = isAtom p
  isAtom _                          = False

  pretty (Div p1 (Plus [Term 1 []])) = pretty p1
  pretty (Div p1 p2)                 = pretty'' p1 ++ " / " ++ pretty' p2
    where
      pretty'' :: PolyExpr -> String
      pretty'' p@(Plus [_]) = pretty p
      pretty'' p            = "(" ++ pretty p ++ ")"

instance Printable PolyExpr where
  isAtom (Plus [])           = True
  isAtom (Plus [Term _ []])  = True
  isAtom (Plus [Term 1 [_]]) = True
  isAtom _                   = False

  pretty (Plus []) = "0"
  pretty (Plus (t:ts)) = pretty t ++ concatMap withSign ts
    where
      withSign (Term a xs) | a < 0 = " - " ++ pretty (Term (- a) xs)
      withSign t                   = " + " ++ pretty t

instance Printable SymbolExpr where
  isAtom Symbol{}     = True
  isAtom (Apply _ []) = True
  isAtom _            = False

  pretty (Symbol _ (':':':':':':_) []) = "#"
  pretty (Symbol _ s []) = s
  pretty (Symbol _ s js) = s ++ concatMap show js
  pretty (Apply fn mExprs) = unwords (map pretty' (fn : mExprs))
  pretty (Quote mExprs) = "'" ++ pretty' mExprs
  pretty (FunctionData name _ _ js) = pretty name ++ concatMap show js

instance Printable TermExpr where
  isAtom (Term _ [])  = True
  isAtom (Term 1 [_]) = True
  isAtom _            = False

  pretty (Term a []) = show a
  pretty (Term 1 xs) = intercalate " * " (map prettyPoweredSymbol xs)
  pretty (Term (-1) xs) = "- " ++ intercalate " * " (map prettyPoweredSymbol xs)
  pretty (Term a xs) = intercalate " * " (show a : map prettyPoweredSymbol xs)

prettyPoweredSymbol :: (SymbolExpr, Integer) -> String
prettyPoweredSymbol (x, 1) = show x
prettyPoweredSymbol (x, n) = pretty' x ++ "^" ++ show n

instance Show ScalarData where
  show = pretty

instance Show PolyExpr where
  show = pretty

instance Show TermExpr where
  show = pretty

instance Show SymbolExpr where
  show = pretty

instance Show (Index ScalarData) where
  show (Superscript i)  = "~" ++ pretty' i
  show (Subscript i)    = "_" ++ pretty' i
  show (SupSubscript i) = "~_" ++ pretty' i
  show (DFscript _ _)   = ""
  show (Userscript i)   = "|" ++ pretty' i
