{-# LANGUAGE TupleSections #-}

{- |
Module      : Language.Egison
Licence     : MIT

This is the top module of Egison.
-}

module Language.Egison
       ( module Language.Egison.AST
       , module Language.Egison.Data
       , module Language.Egison.Primitives
       -- * Eval Egison expressions
       , evalTopExprs
       , evalTopExpr
       , evalEgisonExpr
       , evalEgisonTopExpr
       , evalEgisonTopExprs
       , runEgisonExpr
       , runEgisonTopExpr
       , runEgisonTopExpr'
       , runEgisonTopExprs
       -- * Load Egison files
       , loadEgisonLibrary
       , loadEgisonFile
       -- * Environment
       , initialEnv
       -- * Information
       , version
      ) where

import           Data.Version
import qualified Paths_egison                as P

import           Language.Egison.AST
import           Language.Egison.CmdOptions
import           Language.Egison.Core
import           Language.Egison.Data
import           Language.Egison.MathOutput  (changeOutputInLang)
import           Language.Egison.Parser
import           Language.Egison.Primitives

import           Control.Monad.State

-- |Version number
version :: Version
version = P.version

evalTopExprs :: EgisonOpts -> Env -> [EgisonTopExpr] -> EgisonM Env
evalTopExprs opts env exprs = do
  (bindings, rest) <- collectDefs opts exprs [] []
  env <- recursiveBind env bindings
  forM_ rest $ evalTopExpr opts env
  return env

evalTopExpr :: EgisonOpts -> Env -> EgisonTopExpr -> EgisonM Env
evalTopExpr opts env topExpr = do
  ret <- evalTopExpr' opts (StateT $ \defines -> (, defines) <$> recursiveBind env defines) topExpr
  case fst ret of
    Nothing     -> return ()
    Just output -> liftIO $
            case optMathExpr opts of
              Nothing   -> putStrLn output
              Just lang -> putStrLn $ changeOutputInLang lang output
  evalStateT (snd ret) []

-- |eval an Egison expression
evalEgisonExpr :: Env -> EgisonExpr -> IO (Either EgisonError EgisonValue)
evalEgisonExpr env expr = fromEgisonM $ evalExprDeep env expr

-- |eval an Egison top expression
evalEgisonTopExpr :: EgisonOpts -> Env -> EgisonTopExpr -> IO (Either EgisonError Env)
evalEgisonTopExpr opts env exprs = fromEgisonM $ evalTopExpr opts env exprs

-- |eval Egison top expressions
evalEgisonTopExprs :: EgisonOpts -> Env -> [EgisonTopExpr] -> IO (Either EgisonError Env)
evalEgisonTopExprs opts env exprs = fromEgisonM $ evalTopExprs opts env exprs

-- |eval an Egison expression. Input is a Haskell string.
runEgisonExpr :: EgisonOpts -> Env -> String -> IO (Either EgisonError EgisonValue)
runEgisonExpr opts env input =
  fromEgisonM $ readExpr (optSExpr opts) input >>= evalExprDeep env

-- |eval an Egison top expression. Input is a Haskell string.
runEgisonTopExpr :: EgisonOpts -> Env -> String -> IO (Either EgisonError Env)
runEgisonTopExpr opts env input =
  fromEgisonM $ readTopExpr (optSExpr opts) input >>= evalTopExpr opts env

-- |eval an Egison top expression. Input is a Haskell string.
runEgisonTopExpr' :: EgisonOpts -> StateT [(Var, EgisonExpr)] EgisonM Env -> String -> IO (Either EgisonError (Maybe String, StateT [(Var, EgisonExpr)] EgisonM Env))
runEgisonTopExpr' opts st input =
  fromEgisonM $ readTopExpr (optSExpr opts) input >>= evalTopExpr' opts st

-- |eval Egison top expressions. Input is a Haskell string.
runEgisonTopExprs :: EgisonOpts -> Env -> String -> IO (Either EgisonError Env)
runEgisonTopExprs opts env input =
  fromEgisonM $ readTopExprs (optSExpr opts) input >>= evalTopExprs opts env

-- |load an Egison file
loadEgisonFile :: EgisonOpts -> Env -> FilePath -> IO (Either EgisonError Env)
loadEgisonFile opts env path = evalEgisonTopExpr opts env (LoadFile path)

-- |load an Egison library
loadEgisonLibrary :: EgisonOpts -> Env -> FilePath -> IO (Either EgisonError Env)
loadEgisonLibrary opts env path = evalEgisonTopExpr opts env (Load path)

-- |Environment that contains core libraries
initialEnv :: EgisonOpts -> IO Env
initialEnv opts = do
  env <- if optNoIO opts then primitiveEnvNoIO
                         else primitiveEnv
  ret <- evalEgisonTopExprs defaultOption env $ map Load coreLibraries
  case ret of
    Left err -> do
      print . show $ err
      return env
    Right env' -> return env'

coreLibraries :: [String]
coreLibraries =
  [ "lib/math/expression.segi"
  , "lib/math/normalize.segi"
  , "lib/math/common/arithmetic.segi"
  , "nons-lib/math/common/constants.egi"
  , "nons-lib/math/common/functions.egi"
  , "nons-lib/math/algebra/root.egi"
  , "nons-lib/math/algebra/equations.egi"
  , "nons-lib/math/algebra/inverse.egi"
  , "lib/math/analysis/derivative.segi"
  , "nons-lib/math/analysis/integral.egi"
  , "nons-lib/math/algebra/vector.egi"
  , "nons-lib/math/algebra/matrix.egi"
  , "nons-lib/math/algebra/tensor.egi" -- TODO: change to nons-lib
  , "nons-lib/math/geometry/differential-form.egi"
  , "nons-lib/core/assoc.egi"
  , "nons-lib/core/base.egi"
  , "nons-lib/core/collection.egi"
  , "nons-lib/core/io.egi"
  , "nons-lib/core/maybe.egi"
  , "nons-lib/core/number.egi"
  , "nons-lib/core/order.egi"
  , "nons-lib/core/random.egi"
  , "nons-lib/core/string.egi"
  ]
