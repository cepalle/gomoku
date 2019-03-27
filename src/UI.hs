{-# LANGUAGE OverloadedStrings #-}

module UI where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe)

import qualified Reducer as R

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
import Control.Lens.Combinators (imap)
import Data.Sequence (Seq)
import qualified Data.Sequence as S
import qualified Graphics.Vty as V
import Linear.V2 (V2(..))

-- EVENTS
data Tick =
  Tick

handleEvent :: R.AppState -> BrickEvent Name Tick -> EventM Name (Next R.AppState)
handleEvent g (AppEvent Tick) = continue $ g {R.cursorVisible = not (R.cursorVisible g)}
handleEvent g (VtyEvent (V.EvKey V.KUp [])) = continue $ R.moveCursor g R.CursorUp
handleEvent g (VtyEvent (V.EvKey V.KDown [])) = continue $ R.moveCursor g R.CursorDown
handleEvent g (VtyEvent (V.EvKey V.KRight [])) = continue $ R.moveCursor g R.CursorRight
handleEvent g (VtyEvent (V.EvKey V.KLeft [])) = continue $ R.moveCursor g R.CursorLeft
handleEvent g (VtyEvent (V.EvKey (V.KChar 'p') [])) = continue $ R.placePiece g
handleEvent g (VtyEvent (V.EvKey (V.KChar 'q') [])) = halt g
handleEvent g (VtyEvent (V.EvKey V.KEsc [])) = halt g
handleEvent g _ = continue g

-- DRAWING
drawUI :: R.AppState -> [Widget Name]
drawUI g = [C.center $ drawGrid g]

drawGrid :: R.AppState -> Widget Name
drawGrid R.AppState {R.goGrid = grd, R.cursor = cr, R.cursorVisible = crv} =
  withBorderStyle BS.unicodeBold $ B.borderWithLabel (str "Gomoku") $ vBox rows
  where
    rows = imap cellsInRow grd
    cellsInRow y r = hBox $ imap (drawCell cr crv y) r

drawCell :: (Int, Int) -> Bool -> Int -> Int -> R.Cell -> Widget Name
drawCell (cx, cy) crv y x cell =
  if crv && cx == x && cy == y
    then withAttr cursorAttr cw
    else case cell of
           R.PieceWhite -> withAttr pieceWhiteAttr cw
           R.PieceBlack -> withAttr pieceBlackAttr cw
           R.EmptyCell -> withAttr emptyAttr cw

cw :: Widget Name
cw = str "  "

-- ATTR MAP
theMap :: AttrMap
theMap =
  attrMap
    V.defAttr
    [ (pieceBlackAttr, V.black `on` V.black)
    , (pieceWhiteAttr, V.white `on` V.white)
    , (cursorAttr, V.green `on` V.green)
    , (emptyAttr, V.blue `on` V.blue)
    ]

pieceBlackAttr :: AttrName
pieceBlackAttr = "gameOver"

pieceWhiteAttr :: AttrName
pieceWhiteAttr = "snakeAttr"

cursorAttr :: AttrName
cursorAttr = "cursorAttr"

emptyAttr :: AttrName
emptyAttr = "emptyAttr"

-- MAIN APP
type Name = ()

app :: App R.AppState Tick Name
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
      threadDelay 300000 -- cursor alternator speed
  let buildVty = V.mkVty V.defaultConfig
  initialVty <- buildVty
  void $ customMain initialVty buildVty (Just chan) app R.initState