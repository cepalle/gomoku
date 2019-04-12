module Reducer where

import Constant (allDir, hGoGrid)
import Control.DeepSeq
import Data.List (foldl', sortBy)
import qualified Data.Vector.Unboxed as Vec
import qualified Data.Vector as Vb

-- import Control.Parallel (par)
-- import Data.List (elemIndex)
-- import Data.List.Split (chunksOf)
import Data.Maybe (isJust)

import System.CPUTime

-- import System.IO
-- import System.Random (Random(..), newStdGen)
-- TYPES STATE
data AppState
  = GameState { goGrid :: Grid -- go grid with piece
              , gameMode :: GameMode -- solo or tow player
              , playerTurn :: Player -- turn of player
              , lastIATimeForPlay :: Double -- time for IA play
              , cursorSuggestion :: Maybe Coord -- suggestion IA
              , cursor :: Coord -- user cursor for play
              , cursorVisible :: Bool -- cursor visibility alternator
              , end :: Maybe (Maybe Player) -- Maybe contain player win or Nothing if match null
              , nbPieceCapPWhite :: Int -- nombre de piece capture by player white
              , nbPieceCapPBlack :: Int -- nombre de piece capture by player black
               }
  | Home GameMode
  | SoloSelectPlayer Player
  deriving (Eq, Show)

data Cell
  = PieceBlack
  | PieceWhite
  | EmptyCell
  deriving (Eq, Show)

data Player
  = PlayerWhite
  | PlayerBlack
  deriving (Eq, Show)

data GameMode
  = GameSolo Player
  | GameMulti
  deriving (Eq, Show)

type Coord = (Int, Int)

type Grid = Vec.Vector Char -- length 19 * 19

type GridBool = Vec.Vector Bool -- length 19 * 19

-- INIT STATE
initState :: AppState
initState = Home (GameSolo PlayerWhite)

initGameState :: GameMode -> AppState
initGameState mode =
  let grid = Vec.replicate (hGoGrid * hGoGrid) $ cellToChar EmptyCell
   in GameState
        { goGrid =
            case mode of
              GameSolo PlayerBlack ->
                Vec.imap
                  (\i e ->
                     if i == hGoGrid * 8 + 8
                       then cellToChar PieceWhite
                       else e)
                  grid
              _ -> grid
        , gameMode = mode
        , playerTurn =
            case mode of
              GameSolo PlayerBlack -> PlayerBlack
              _ -> PlayerWhite
        , lastIATimeForPlay = 0.0
        , cursorSuggestion = Nothing
        , cursor = (9, 9)
        , cursorVisible = True
        , end = Nothing
        , nbPieceCapPBlack = 0
        , nbPieceCapPWhite = 0
        }

-- UPDATE STATE
data CursorDir
  = CursorUp
  | CursorDown
  | CursorRight
  | CursorLeft

moveCursor :: AppState -> CursorDir -> (Int, Int)
moveCursor GameState {cursor = (x, y)} d =
  case d of
    CursorUp -> (x, (y - 1) `mod` hGoGrid)
    CursorDown -> (x, (y + 1) `mod` hGoGrid)
    CursorRight -> ((x + 1) `mod` hGoGrid, y)
    CursorLeft -> ((x - 1) `mod` hGoGrid, y)
moveCursor _ _ = (0, 0)

handelPlayCoord :: Coord -> AppState -> AppState
handelPlayCoord cr s =
  case end s of
    Nothing ->
      if validCoord (goGrid s) (playerTurn s) cr
        then let nwS = checkEnd cr $ checkCaptur cr $ s {goGrid = posePiece cr (playerTurn s) (goGrid s)}
              in nwS {playerTurn = nextPlayer (playerTurn s)}
        else s
    _ -> s

posePiece :: Coord -> Player -> Grid -> Grid
posePiece (cx, cy) p grid = Vec.imap putPiece grid
  where
    putPiece :: Int -> Char -> Char
    putPiece idx c =
      if idx == hGoGrid * cy + cx
        then playerToChar p
        else c

posePieceAndDelete :: Coord -> Player -> Grid -> Grid
posePieceAndDelete cr p grd =
  let withPiece :: Grid
      withPiece = posePiece cr p grd
      toSup :: [[(Int, Int, Player)]]
      toSup = checkCapturToSup p cr withPiece
      newGrd = supPosGrid withPiece toSup
   in newGrd

checkCaptur :: Coord -> AppState -> AppState
checkCaptur cr s =
  let toSup = checkCapturToSup (playerTurn s) cr (goGrid s)
      nbCap = length toSup * 2
      newGrd = supPosGrid (goGrid s) toSup
   in case playerTurn s of
        PlayerBlack -> s {goGrid = newGrd, nbPieceCapPBlack = nbPieceCapPBlack s + nbCap}
        PlayerWhite -> s {goGrid = newGrd, nbPieceCapPWhite = nbPieceCapPWhite s + nbCap}

-- To modify
mapMemoCapturToSup :: (Vb.Vector [[(Int, Int, Player)]], Vb.Vector [[(Int, Int, Player)]])
mapMemoCapturToSup =
  let grid = Vb.replicate (hGoGrid * hGoGrid) True
      mw = Vb.imap (\i _ -> map (genPosCheck (mod i hGoGrid, div i hGoGrid) PlayerWhite) allDir) grid
      mb = Vb.imap (\i _ -> map (genPosCheck (mod i hGoGrid, div i hGoGrid) PlayerBlack) allDir) grid
   in (mw, mb)
  where
    genPosCheck (cx, cy) player (dx, dy) =
      [ (cx + dx, cy + dy, nextPlayer player)
      , (cx + dx * 2, cy + dy * 2, nextPlayer player)
      , (cx + dx * 3, cy + dy * 3, player)
      ]

checkCapturToSup :: Player -> Coord -> Grid -> [[(Int, Int, Player)]]
checkCapturToSup p (cx, cy) grd =
  let (mw, mn) = mapMemoCapturToSup
      toCheck :: Vb.Vector [[(Int, Int, Player)]]
      toCheck =
        if p == PlayerWhite
          then mw
          else mn
   in filter (checkPoss grd) $ toCheck Vb.! (cy * hGoGrid + cx)
  where
    checkPoss :: Grid -> [(Int, Int, Player)] -> Bool
    checkPoss grid psCks = length (filter (checkPos grid) psCks) == 3
    checkPos :: Grid -> (Int, Int, Player) -> Bool
    checkPos gd (x, y, plr) =
      x >= 0 && x < hGoGrid && y >= 0 && y < hGoGrid && gd Vec.! (hGoGrid * y + x) == playerToChar plr

supPosGrid :: Grid -> [[(Int, Int, Player)]] -> Grid
supPosGrid grd toSup = foldl' supElGrd grd toSup
  where
    supElGrd :: Grid -> [(Int, Int, Player)] -> Grid
    supElGrd gd poss =
      let (fx, fy, _) = head poss
          (sx, sy, _) = poss !! 1
       in Vec.imap
            (\i e ->
               if i == (fy * hGoGrid + fx) || i == (sy * hGoGrid + sx)
                 then cellToChar EmptyCell
                 else e)
            gd

handelIAPlay :: AppState -> IO AppState
handelIAPlay s = do
  start <- getCPUTime
  let mCoord = solver (goGrid s) (playerTurn s) (nbPieceCapPWhite s) (nbPieceCapPBlack s)
  endTimer <- mCoord `deepseq` getCPUTime
  let diff = fromIntegral (endTimer - start) / (10 ^ 9)
  let withDiff = s {lastIATimeForPlay = diff}
  return (handelPlayCoord mCoord withDiff)

suggestionPlay :: AppState -> IO AppState
suggestionPlay s =
  if isJust (end s)
    then return s
    else do
      start <- getCPUTime
      let coord = solver (goGrid s) (playerTurn s) (nbPieceCapPWhite s) (nbPieceCapPBlack s)
      endTimer <- coord `deepseq` getCPUTime
      let diff = fromIntegral (endTimer - start) / (10 ^ 9)
      return s {lastIATimeForPlay = diff, cursorSuggestion = Just coord}

-- UTIL
playerToPiece :: Player -> Cell
playerToPiece PlayerWhite = PieceWhite
playerToPiece PlayerBlack = PieceBlack

nextPlayer :: Player -> Player
nextPlayer PlayerWhite = PlayerBlack
nextPlayer PlayerBlack = PlayerWhite

playerToChar :: Player -> Char
playerToChar PlayerWhite = '1'
playerToChar PlayerBlack = '2'

cellToChar :: Cell -> Char
cellToChar EmptyCell = '0'
cellToChar PieceWhite = '1'
cellToChar PieceBlack = '2'

charToCell :: Char -> Cell
charToCell '0' = EmptyCell
charToCell '1' = PieceWhite
charToCell '2' = PieceBlack
charToCell _ = EmptyCell

-- can use delDoubleThree
validCoords :: Grid -> Player -> GridBool
validCoords grd p = delDoubleThree grd p (Vec.map (== cellToChar EmptyCell) grd)

validCoord :: Grid -> Player -> Coord -> Bool
validCoord grd p (cx, cy) =
  cx >= 0 && cx < hGoGrid && cy >= 0 && cy < hGoGrid && validCoords grd p Vec.! (cy * hGoGrid + cx)

validCoordToList :: GridBool -> [(Int, Int)]
validCoordToList grid = [(x, y) | x <- [0 .. hGoGrid - 1], y <- [0 .. hGoGrid - 1], grid Vec.! (y * hGoGrid + x)]

checkEnd :: Coord -> AppState -> AppState
checkEnd cr s
  | nbPieceCapPWhite s >= 10 = s {end = Just (Just PlayerWhite)}
  | nbPieceCapPBlack s >= 10 = s {end = Just (Just PlayerBlack)}
  | checkAlign5 cr (goGrid s) (playerTurn s) = s {end = Just (Just (playerTurn s))}
  | 0 == Vec.length (Vec.filter id $ validCoords (goGrid s) (playerTurn s)) = s {end = Just Nothing}
  | otherwise = s
  where
    checkAlign5 :: Coord -> Grid -> Player -> Bool
    checkAlign5 c grd p = checkAllPos grd p $ allDir >>= genPosCheck c
    maskCoef :: [[Int]]
    maskCoef = [[-4, -3, -2, -1, 0], [-3, -2, -1, 0, 1], [-2, -1, 0, 1, 2]]
    genPosCheck :: Coord -> Coord -> [[Coord]]
    genPosCheck (cx, cy) (dx, dy) = map (map (\k -> (cx + dx * k, cy + dy * k))) maskCoef
    checkAllPos :: Grid -> Player -> [[Coord]] -> Bool
    checkAllPos grd p lpos =
      let tmp = map (length . filter (checkPos grd p)) lpos
       in (0 /= length (filter (== 5) tmp))
    checkPos :: Grid -> Player -> Coord -> Bool
    checkPos grd p (x, y) =
      x >= 0 && x < hGoGrid && y >= 0 && y < hGoGrid && grd Vec.! (y * hGoGrid + x) == playerToChar p

------------
-- SOLVER --
------------
-- OPTI ?
-- Constant Empty Grid ?
mapMemoDoubleThree :: (Vb.Vector [([(Int, Int, Cell)], (Int, Int))], Vb.Vector [([(Int, Int, Cell)], (Int, Int))])
mapMemoDoubleThree =
  let grid = Vb.replicate (hGoGrid * hGoGrid) True
      maskWhite = maskCoef $ playerToPiece PlayerWhite
      maskBlack = maskCoef $ playerToPiece PlayerBlack
      genWhite = Vb.imap (\i _ ->  allDir >>= genPosCheck maskWhite (mod i hGoGrid, div i hGoGrid)) grid
      genBlack = Vb.imap (\i _ ->  allDir >>= genPosCheck maskBlack (mod i hGoGrid, div i hGoGrid)) grid
   in (genWhite, genBlack)
  where
    maskCoef :: Cell -> [[(Int, Cell)]]
    maskCoef pc =
      [ [(-3, EmptyCell), (-2, pc), (-1, pc), (0, EmptyCell), (1, EmptyCell)]
      , [(-2, EmptyCell), (-1, pc), (0, EmptyCell), (1, pc), (2, EmptyCell)]
      , [(-4, EmptyCell), (-3, pc), (-2, pc), (-1, EmptyCell), (0, EmptyCell), (1, EmptyCell)]
      , [(-2, EmptyCell), (-1, pc), (0, EmptyCell), (1, EmptyCell), (2, pc), (3, EmptyCell)]
      , [(-1, EmptyCell), (0, EmptyCell), (1, pc), (2, EmptyCell), (3, pc), (4, EmptyCell)]
      ]
    genPosCheck :: [[(Int, Cell)]] -> Coord -> Coord -> [([(Int, Int, Cell)], (Int, Int))]
    genPosCheck msk (cx, cy) (dx, dy) = map (\r -> (map (\(k, c) -> (cx + dx * k, cy + dy * k, c)) r, (dx, dy))) msk

delDoubleThree :: Grid -> Player -> GridBool -> GridBool
delDoubleThree grd p grd_old =
  let (mw, mn) = mapMemoDoubleThree
      toCheck =
        if p == PlayerWhite
          then mw
          else mn
   in Vec.imap (\i e -> e && checkAllPos grd (toCheck Vb.! i)) grd_old
  where
    checkAllPos :: Grid -> [([(Int, Int, Cell)], (Int, Int))] -> Bool
    checkAllPos grida lpos =
      let tmp = map snd $ filter (checkLPos grida) lpos
          dDir = foldl' delDir [] tmp
       in 1 >= length dDir
    checkLPos :: Grid -> ([(Int, Int, Cell)], (Int, Int)) -> Bool
    checkLPos grd' (lp, _) = length lp == length (filter (checkPos grd') lp)
    checkPos :: Grid -> (Int, Int, Cell) -> Bool
    checkPos grid (x, y, pc) =
      x >= 0 && x < hGoGrid && y >= 0 && y < hGoGrid && grid Vec.! (y * hGoGrid + x) == cellToChar pc
    delDir :: [(Int, Int)] -> (Int, Int) -> [(Int, Int)]
    delDir acc (drx, dry) = filter (\(dx, dy) -> not (drx == negate dx && dry == negate dy)) $ acc ++ [(drx, dry)]

-- True if is dist <= maxDist
distEmptyCellMap :: Grid -> Int -> GridBool
distEmptyCellMap grille maxDist =
  let initMap = Vec.map (== cellToChar EmptyCell) grille
      iterator = [1 .. maxDist]
   in Vec.map not $ foldl' (\b _ -> addDist1 b) initMap iterator
  where
    addDist1 :: GridBool -> GridBool
    addDist1 grid = Vec.imap (\i e -> e && not (checkNeighbour grid (mod i hGoGrid) (div i hGoGrid))) grid
    checkNeighbour :: GridBool -> Int -> Int -> Bool
    checkNeighbour grd x y =
      checkPos grd (x + 1) y ||
      checkPos grd x (y + 1) ||
      checkPos grd x (y - 1) ||
      checkPos grd (x - 1) y ||
      checkPos grd (x + 1) (y + 1) ||
      checkPos grd (x + 1) (y - 1) || checkPos grd (x - 1) (y + 1) || checkPos grd (x - 1) (y - 1)
    checkPos :: GridBool -> Int -> Int -> Bool
    checkPos gd x y = x >= 0 && x < hGoGrid && y >= 0 && y < hGoGrid && not (gd Vec.! (y * hGoGrid + x))

moreThanOne :: Grid -> Coord -> Int -> (Int, Int) -> Int
moreThanOne grid (cx, cy) count direction
  | count > 1 = 2
  | 0 > cx || 0 > cy = count
  | (hGoGrid - 1) < cx || (hGoGrid - 1) < cy = count
  | cellToChar EmptyCell == gridPiece = count
  | otherwise = moreThanOne grid (sumTuples (cx, cy) direction) (count + 1) direction
  where
    gridPiece = grid Vec.! (cy * hGoGrid + cx)

worthMoveIA :: Grid -> Coord -> Bool
worthMoveIA grid move = True `elem` render
  where
    dirCouples = [(0, 5), (1, 4), (2, 3), (6, 7)]
    removeCoordIA :: Grid -> Coord -> (Int, Int) -> Int
    removeCoordIA grd mv direction = moreThanOne grd (sumTuples mv direction) 0 direction
    sumDir = map (removeCoordIA grid move) allDir
    render = [isTrue >= 2 | x <- dirCouples, let isTrue = (sumDir !! fst x) + (sumDir !! snd x)]

-- /!\ no valide play if the map is Empty!
validIACoords :: Grid -> Player -> Int -> GridBool
validIACoords grd p d =
  let empty = Vec.map (== cellToChar EmptyCell) grd
      grd_dist = distEmptyCellMap grd d
      emptyAndDist = Vec.imap (\i e -> e && grd_dist Vec.! i) empty
      optiMoves = Vec.imap (\idx e -> let m = (mod idx hGoGrid, div idx hGoGrid)
                                      in e && worthMoveIA grd m) emptyAndDist
      moves = if Vec.length (Vec.filter id optiMoves) > 4
              then optiMoves
              else emptyAndDist
      v = delDoubleThree grd p moves
   in v

sumTuples :: (Int, Int) -> (Int, Int) -> (Int, Int)
sumTuples (a1, a2) (b1, b2) = (a1 + b1, a2 + b2)

------------
-- SOLVER --
------------
solver :: Grid -> Player -> Int -> Int -> Coord
solver = miniWrapper

countDir :: Grid -> Player -> Coord -> (Int, Int) -> Int
countDir grid player (cx, cy) (dx, dy) =
  let (_, nb) = foldl' sumDist (True, 0) [1 .. 4]
   in nb
  where
    sumDist (b, nb) d =
      let (cx', cy') = (cx + d * dx, cy + d * dy)
       in if b &&
             0 <= cx' &&
             0 <= cy' && hGoGrid > cx' && hGoGrid > cy' && grid Vec.! (cy' * hGoGrid + cx') == playerToChar player
            then (True, nb + 1)
            else (False, nb)

moveScoring :: Grid -> Int -> Int -> Player -> Coord -> (Int, Int, Int)
moveScoring grid capWhite capBlack player move =
  let countedDir = map (countDir grid player move) allDir
      sumSameDir = map (\(c1, c2) -> (countedDir !! c1) + (countedDir !! c2) + 1) [(0, 5), (1, 4), (2, 3), (6, 7)]
      newCap = 2 * length (checkCapturToSup player move grid)
      nbCap =
        if player == PlayerWhite
          then capWhite + newCap
          else capBlack + newCap
      scoreCapture =
        if nbCap == 10
          then 1000000
          else 10000 * nbCap
      score = scoreCapture + foldl' transformToScore 0 sumSameDir
   in if player == PlayerWhite
        then (score, nbCap, capBlack)
        else (score, capWhite, nbCap)
  where
    countToScore count
      | count == 0 = 0
      | count == 1 = 1
      | count == 2 = 10
      | count == 3 = 100
      | count == 4 = 1000
      | otherwise = 1000000
    transformToScore :: Int -> Int -> Int
    transformToScore precSco count = precSco + countToScore count

nextMoves :: Grid -> Player -> [Coord]
nextMoves grid player =
  let moves = validCoordToList $ validIACoords grid player 1
   in if null moves
      then validCoordToList $ validCoords grid player
      else moves

negaMax :: Grid -> Player -> Int -> Int -> Int -> Int -> Int -> Int
negaMax grid player depth alpha beta capWhite capBlack =
  let moves = nextMoves grid player
      nxtMovesAndScore :: [(Coord, (Int, Int, Int))]
      nxtMovesAndScore = map (\(cx, cy) -> ((cx, cy), moveScoring grid capWhite capBlack player (cx, cy))) moves
      movesSort = sortBy compF nxtMovesAndScore
      abPruning a ((cx, cy), (prSc, nW, nB)) =
        if a >= beta
          then a
          else let newGrid = posePieceAndDelete (cx, cy) player grid
                   resNega =
                     if prSc < 500000
                       then prSc - negaMax newGrid (nextPlayer player) (depth - 1) (-beta) (-a) nW nB
                       else prSc
                   newAlpha = max a resNega
                in newAlpha
      res =
        if depth > 0
          then foldl' abPruning alpha movesSort
          else maximum $ map (\(_, (s, _, _)) -> s) movesSort
   in res
  where
    compF :: (Coord, (Int, Int, Int)) -> (Coord, (Int, Int, Int)) -> Ordering
    compF (_, (s1, _, _)) (_, (s2, _, _))
      | s1 > s2 = LT
      | s1 < s2 = GT
      | otherwise = EQ

miniWrapper :: Grid -> Player -> Int -> Int -> Coord
miniWrapper grid player capWhite capBlack =
  let depth = 3 -- In reality depth = depth + 2
      alpha = div (minBound :: Int) 8
      beta = div (maxBound :: Int) 8
      moves = nextMoves grid player
      nxtMovesAndScore :: [(Coord, (Int, Int, Int))]
      nxtMovesAndScore = map (\(cx, cy) -> ((cx, cy), moveScoring grid capWhite capBlack player (cx, cy))) moves
      movesSort = sortBy compF nxtMovesAndScore
      abPruning (a, co) ((cx, cy), (prSc, nW, nB)) =
        if a >= beta
          then (a, co)
          else let newGrid = posePieceAndDelete (cx, cy) player grid
                   resNega =
                     if prSc < 500000
                       then prSc - negaMax newGrid (nextPlayer player) depth (-beta) (-a) nW nB
                       else prSc
                in if resNega > a
                     then (resNega, (cx, cy))
                     else (a, co)
      (_, bestMove) = foldl' abPruning (alpha, (-1, -1)) movesSort
   in bestMove
  where
    compF :: (Coord, (Int, Int, Int)) -> (Coord, (Int, Int, Int)) -> Ordering
    compF (_, (s1, _, _)) (_, (s2, _, _))
      | s1 > s2 = LT
      | s1 < s2 = GT
      | otherwise = EQ
