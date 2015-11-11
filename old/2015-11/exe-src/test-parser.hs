{-# LANGUAGE TemplateHaskell #-}
module Main where

import Control.Applicative
import Control.Lens
import Control.Monad
import Data.Maybe
import Data.Monoid
import qualified Data.Traversable as Tr
import qualified Data.Text.IO as T
import qualified Data.Map as M
import qualified Data.Set as S
import System.Environment
import System.IO
import Text.Trifecta
import Text.Printf
import Text.PrettyPrint.ANSI.Leijen as Pretty hiding (line, (<>), (<$>), empty, integer)

import Language.Formura.AST
import Language.Formura.Tree
import Language.Formura.Parser
import Language.Formura.Enforest



tSepBy :: SymbolName -> Tree -> [Tree]
tSepBy n t0 = go t0
  where
    go :: Tree -> [Tree]
    go t@Binary{_treeCar=SymbolLeaf{_treeSymbol=n}, _treeLhs=lhs, _treeRhs=rhs}
                 = tSepBy n lhs ++ tSepBy n rhs
    go t = [t]

definedName :: Tree -> SymbolName
definedName t@(RationalLeaf{}) = abortCompilerAt t "unexpected literal" [] ["variable name"]
definedName (SymbolLeaf{_treeSymbol=s}) = s
definedName (Binary{_treeLhs=t}) = definedName t
definedName (Unary{_treeRhs=t}) = definedName t


data Knowledge -- A Knowledge about a symbol
 = Knowledge { _knowSpecialDeclaration :: Maybe Tree
             , _knowTypeDeclaration :: Maybe Tree
             , _knowSubstitution :: Maybe Tree}
makeClassy ''Knowledge


defaultKnowledge :: Knowledge
defaultKnowledge = Knowledge Nothing Nothing Nothing


mergeKnowledge :: Knowledge -> Knowledge -> Knowledge
mergeKnowledge (Knowledge as at ad) (Knowledge bs bt bd)
  = Knowledge (mg "special declaration" as bs)
              (mg "type declaration" at bt)
              (mg "substitution" ad bd)
  where
    mg :: String -> Maybe Tree -> Maybe Tree -> Maybe Tree
    mg what (Just a) (Just b) = abortCompilerAtRs [a ^. rendering, b ^. rendering] ("duplicated " ++ what) [] []
    mg _ a b = a <|> b

specialDeclarationKeywords :: [SymbolName]
specialDeclarationKeywords = ["initial_state", "current_state", "next_state"]

isSpecialDeclarationSymbol :: Tree -> Bool
isSpecialDeclarationSymbol SymbolLeaf{_treeSymbol=s}
  | s `elem` specialDeclarationKeywords = True
  | otherwise                           = False
isSpecialDeclarationSymbol _ = False

treeToKnowledge :: Tree -> [(SymbolName, Knowledge)]
treeToKnowledge t0@Binary{_treeCar=SymbolLeaf{_treeSymbol="::"}, _treeLhs=lhs, _treeRhs=rhs}
  = let k :: Tree -> Knowledge
        k n = case isSpecialDeclarationSymbol lhs
                of True -> defaultKnowledge{_knowSpecialDeclaration = Just lhs}
                   False-> defaultKnowledge{_knowTypeDeclaration = Just t0{_treeLhs=n, _treeRhs=lhs}}
    in [(definedName n,k n) | n <- tSepBy "," rhs]
treeToKnowledge t0@Binary{_treeCar=SymbolLeaf{_treeSymbol="="}, _treeLhs=lhs, _treeRhs=rhs}
               = [(definedName lhs,defaultKnowledge{_knowSubstitution = Just t0}) ]
treeToKnowledge t = abortCompilerAt t "unknown kind of sentence" [] ["declaration", "substitution"]


analyze :: [Tree] -> IO ()
analyze progTree = do
  let kmap :: M.Map SymbolName Knowledge
      kmap = M.fromListWith mergeKnowledge $ progTree >>= treeToKnowledge

  let showKnowledge klens = mapM_ print $ catMaybes $
        map Tr.sequence $ -- :: (a, Maybe b) -> Maybe (a,b)
        map (_2 %~ klens) $ M.toList $ kmap

  putStrLn "#### Special Decls ####"
  showKnowledge _knowSpecialDeclaration

  putStrLn "#### Type Decls ####"
  showKnowledge _knowTypeDeclaration

  putStrLn "#### Substitutions ####"
  showKnowledge _knowSubstitution

  let bind :: Binding
      bind = M.map (evalK bind)  kmap

  putStrLn "#### Eval ####"
  mapM_ print $ M.toList bind


type Binding = M.Map SymbolName FValue

todo [] = FVString "TODO"
todo x = FVString $ "TODO " ++ x

-- -- transformBin (a,b) = case (a,b) of
-- --   (FVRange)

evalK :: Binding -> Knowledge -> FValue
evalK binding k = case k ^.knowSubstitution of
  Just t -> eval binding (_treeRhs t)
  Nothing -> todo ""

eval :: Binding -> Tree -> FValue
eval binding t = case t of
  RationalLeaf _ r -> FVRational r
  SymbolLeaf m s -> case M.lookup s binding  of
    Just v -> v
    Nothing -> abortCompilerAt m "undefined symbol" [] []
  Binary m o l r -> case _treeSymbol o of
    "+" -> fromMaybe (todo $ show t) $ do
      let FVRational lv = eval binding l
          FVRational rv = eval binding r
      return $ FVRational $ lv + rv
    "-" -> fromMaybe (todo $ show t) $ do
      let FVRational lv = eval binding l
          FVRational rv = eval binding r
      return $ FVRational $ lv - rv
    "*" -> fromMaybe (todo $ show t) $ do
      let FVRational lv = eval binding l
          FVRational rv = eval binding r
      return $ FVRational $ lv * rv
    "/" -> fromMaybe (todo $ show t) $ do
      let FVRational lv = eval binding l
          FVRational rv = eval binding r
      return $ FVRational $ lv / rv
    "**" -> fromMaybe (todo $ show t) $ do
      let FVRational lv = eval binding l
          FVRational rv = eval binding r
      return $ FVRational $ lv ^ (round rv::Int)
    _   -> todo $ show t
  _ -> todo ""

main :: IO ()
main = do
  (fileName:_ ) <- getArgs
  res <- parseFromFileEx (internalP program <* eof) fileName
  case res of
    Success ast -> do
      putStrLn "#### Tokenized Program ####"
      print ast

      let progTree :: [Tree]
          progTree = readProgram ast
      putStrLn "#### Enforested Program ####"
      mapM_ print progTree
      analyze progTree

    Failure doc -> displayIO stdout $ renderPretty 0.8 80 $ doc <> linebreak