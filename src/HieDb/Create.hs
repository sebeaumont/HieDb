{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ViewPatterns #-}
module HieDb.Create where

import Prelude hiding (mod)

import GHC
import HieTypes

import Control.Monad.IO.Class

import System.Directory

import Database.SQLite.Simple

import HieDb.Types
import HieDb.Utils

withHieDb :: FilePath -> (HieDb -> IO a) -> IO a
withHieDb fp f = withConnection fp (f . HieDb)

initConn :: HieDb -> IO ()
initConn (getConn -> conn) = do
  execute_ conn "CREATE TABLE IF NOT EXISTS refs (src TEXT, srcMod TEXT, srcUnit TEXT, occ TEXT, mod TEXT, unit TEXT, file TEXT, sl INTEGER, sc INTEGER, el INTEGER, ec INTEGER)"
  execute_ conn "CREATE TABLE IF NOT EXISTS mods (hieFile TEXT PRIMARY KEY ON CONFLICT REPLACE, mod TEXT, unit TEXT, time TEXT, CONSTRAINT modid UNIQUE (mod, unit) ON CONFLICT REPLACE)"

addRefsFrom :: (MonadIO m, NameCacheMonad m) => HieDb -> FilePath -> m ()
addRefsFrom (getConn -> conn) path = do
  time <- liftIO $ getModificationTime path
  mods <- liftIO $ query conn "SELECT * FROM mods WHERE hieFile = ? AND time >= ?" (path, time)
  case mods of
    (HieModuleRow{}:_) -> return ()
    [] -> withHieFile path $ \hf -> liftIO $ withTransaction conn $ do
      execute conn "DELETE FROM refs WHERE src = ?" (Only path)
      let mod = moduleName $ hie_module hf
          uid = moduleUnitId $ hie_module hf
          modrow = HieModuleRow path mod uid time
      execute conn "INSERT INTO mods VALUES (?,?,?,?)" modrow
      let rows = genRefRow path hf
      executeMany conn "INSERT INTO refs VALUES (?,?,?,?,?,?,?,?,?,?,?)" rows

deleteFileFromIndex :: HieDb -> FilePath -> IO ()
deleteFileFromIndex (getConn -> conn) path = liftIO $ withTransaction conn $ do
  execute conn "DELETE FROM mods WHERE hieFile = ?" (Only path)
  execute conn "DELETE FROM refs WHERE src = ?" (Only path)
