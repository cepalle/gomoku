{-# LANGUAGE OverloadedStrings #-}

module UI where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe)

import Snake

import Brick
  ( App(..)
  , AttrMap
  , AttrName
  , BrickEvent(..)
  , EventM
  , Next
  , Padding(..)
  , Widget
  , (<+>)
  , attrMap
  , continue
  , customMain
  , emptyWidget
  , fg
  , hBox
  , hLimit
  , halt
  , neverShowCursor
  , on
  , padAll
  , padLeft
  , padRight
  , padTop
  , str
  , vBox
  , vLimit
  , withAttr
  , withBorderStyle
  )
import Brick.BChan (newBChan, writeBChan)
import qualified Brick.Widgets.Border as B
import qualified Brick.Widgets.Border.Style as BS
import qualified Brick.Widgets.Center as C
import Control.Lens ((^.))
import Data.Sequence (Seq)
import qualified Data.Sequence as S
import qualified Graphics.Vty as V
import Linear.V2 (V2(..))

-- Custom event types
data Tick =
  Tick

-- Not currently used, but will be easier to refactor
type Name = ()

data Cell
  = Snake
  | Food
  | Empty

-- App definition
app :: App AppState Tick Name
app =
  App
    { appDraw = drawUI
    , appChooseCursor = neverShowCursor
    , appHandleEvent = handleEvent
    , appStartEvent = return
    , appAttrMap = const theMap
    }

main :: IO ()
main = do
  chan <- newBChan 10
  forkIO $
    forever $ do
      writeBChan chan Tick
      threadDelay 100000 -- decides how fast your game moves
  g <- initGame
  let buildVty = V.mkVty V.defaultConfig
  initialVty <- buildVty
  void $ customMain initialVty buildVty (Just chan) app g

-- Handling events
handleEvent :: AppState -> BrickEvent Name Tick -> EventM Name (Next AppState)
handleEvent g (AppEvent Tick) = continue $ step g
handleEvent g (VtyEvent (V.EvKey V.KUp [])) = continue $ turn North g
handleEvent g (VtyEvent (V.EvKey V.KDown [])) = continue $ turn South g
handleEvent g (VtyEvent (V.EvKey V.KRight [])) = continue $ turn East g
handleEvent g (VtyEvent (V.EvKey V.KLeft [])) = continue $ turn West g
handleEvent g (VtyEvent (V.EvKey (V.KChar 'k') [])) = continue $ turn North g
handleEvent g (VtyEvent (V.EvKey (V.KChar 'j') [])) = continue $ turn South g
handleEvent g (VtyEvent (V.EvKey (V.KChar 'l') [])) = continue $ turn East g
handleEvent g (VtyEvent (V.EvKey (V.KChar 'h') [])) = continue $ turn West g
handleEvent g (VtyEvent (V.EvKey (V.KChar 'r') [])) = liftIO (initGame) >>= continue
handleEvent g (VtyEvent (V.EvKey (V.KChar 'q') [])) = halt g
handleEvent g (VtyEvent (V.EvKey V.KEsc [])) = halt g
handleEvent g _ = continue g

-- Drawing
drawUI :: AppState -> [Widget Name]
drawUI g = [C.center $ padRight (Pad 2) (drawStats g) <+> drawGrid g]

drawStats :: AppState -> Widget Name
drawStats g = hLimit 11 $ vBox [drawScore (g ^. score), padTop (Pad 2) $ drawGameOver (g ^. dead)]

drawScore :: Int -> Widget Name
drawScore n = withBorderStyle BS.unicodeBold $ B.borderWithLabel (str "Score") $ C.hCenter $ padAll 1 $ str $ show n

drawGameOver :: Bool -> Widget Name
drawGameOver dead =
  if dead
    then withAttr gameOverAttr $ C.hCenter $ str "GAME OVER"
    else emptyWidget

drawGrid :: AppState -> Widget Name
drawGrid g = withBorderStyle BS.unicodeBold $ B.borderWithLabel (str "Snake") $ vBox rows
  where
    rows = [hBox $ cellsInRow r | r <- [height - 1,height - 2 .. 0]]
    cellsInRow y = [drawCoord (V2 x y) | x <- [0 .. width - 1]]
    drawCoord = drawCell . cellAt
    cellAt c
      | c `elem` g ^. snake = Snake
      | c == g ^. food = Food
      | otherwise = Empty

drawCell :: Cell -> Widget Name
drawCell Snake = withAttr snakeAttr cw
drawCell Food = withAttr foodAttr cw
drawCell Empty = withAttr emptyAttr cw

cw :: Widget Name
cw = str "  "

-- AttrMap
theMap :: AttrMap
theMap =
  attrMap
    V.defAttr
    [(snakeAttr, V.blue `on` V.blue), (foodAttr, V.red `on` V.red), (gameOverAttr, fg V.red `V.withStyle` V.bold)]

gameOverAttr :: AttrName
gameOverAttr = "gameOver"

snakeAttr :: AttrName
snakeAttr = "snakeAttr"

foodAttr :: AttrName
foodAttr = "foodAttr"

emptyAttr :: AttrName
emptyAttr = "emptyAttr"
