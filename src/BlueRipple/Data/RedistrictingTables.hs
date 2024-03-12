{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module BlueRipple.Data.RedistrictingTables
  (
    module BlueRipple.Data.RedistrictingTables
  )
where

import qualified BlueRipple.Data.Small.DataFrames as BR
import qualified BlueRipple.Data.Types.Geographic as GT
import qualified BlueRipple.Data.Small.Loaders as BR
import BlueRipple.Data.ACS_Tables_Loaders (noMaps)
import qualified BlueRipple.Data.ACS_Tables as ACS
import qualified BlueRipple.Data.CachingCore as BRCC
import qualified Control.Foldl as FL
import Control.Lens ((^.))
import qualified Data.Map as M
import qualified Data.Set as S
--import Data.Serialize.Text ()
import qualified Data.Vinyl as V
import qualified Frames as F
import qualified Frames.Streamly.TH as FS
import qualified Frames.Streamly.ColumnUniverse as FCU
import qualified Knit.Report as K
import qualified Language.Haskell.TH.Env as Env


FS.declareColumn "PlanName" ''Text

draDataPath :: Text
draDataPath = fromMaybe "data" $ ($$(Env.envQ "BR_DRA_DATA_DIR") :: Maybe String) >>= BRCC.insureFinalSlash . toText


bigDataPath :: Text
bigDataPath = fromMaybe "../bigData/" $ ($$(Env.envQ "BR_BIG_DATA_DIR") :: Maybe String) >>= BRCC.insureFinalSlash . toText

type RedistrictingPlanIdR = [GT.StateAbbreviation, PlanName, GT.DistrictTypeC]
type RedistrictingPlanId = F.Record RedistrictingPlanIdR
data RedistrictingPlanFiles = RedistrictingPlanFiles { districtDemographicsFP :: Text, districtAnalysisFP :: Text } deriving stock Show

redistrictingPlanId :: Text -> Text -> GT.DistrictType -> RedistrictingPlanId
redistrictingPlanId sa name dt = sa F.&: name F.&: dt F.&: V.RNil

planIdText :: RedistrictingPlanId -> Text
planIdText r = "state=" <> r ^. GT.stateAbbreviation <> " for " <> show (r ^. GT.districtTypeC) <> " districts (" <> r ^. planName <> ")"

{-
plans :: Map RedistrictingPlanId RedistrictingPlanFiles
plans = M.fromList
  [
    (redistrictingPlanId "NC" "Passed" ET.Congressional, RedistrictingPlanFiles "../bigData/Census/cd117_NC.csv" "data/redistricting/NC_congressional.csv")
  , (redistrictingPlanId "NC" "Passed" ET.StateUpper, RedistrictingPlanFiles "../bigData/Census/nc_2022_sldu.csv" "data/redistricting/nc_2022_sldu.csv")
  , (redistrictingPlanId "NC" "Passed" ET.StateLower, RedistrictingPlanFiles "../bigData/Census/nc_2022_sldl.csv" "data/redistricting/nc_2022_sldl.csv")
  , (redistrictingPlanId "TX" "Passed" ET.Congressional, RedistrictingPlanFiles "../bigData/Census/cd117_TX.csv" "data/redistricting/TX-proposed.csv")
  , (redistrictingPlanId "AZ" "Passed" ET.Congressional, RedistrictingPlanFiles "../bigData/Census/az_cd117.csv" "data/redistricting/az_congressional.csv")
  , (redistrictingPlanId "AZ" "Passed" ET.StateUpper, RedistrictingPlanFiles "../bigData/Census/az_sld.csv" "data/redistricting/az_SLD.csv")
  ]
-}

allPassedCongressionalPlans ::  (K.KnitEffects r, BRCC.CacheEffects r)
                            => Int -> ACS.TableYear -> K.Sem r  (Map RedistrictingPlanId RedistrictingPlanFiles)
allPassedCongressionalPlans mapYear acsTableYear = do
  stateInfo <- K.ignoreCacheTimeM BR.stateAbbrCrosswalkLoader
  let states = FL.fold (FL.premap (F.rgetField @GT.StateAbbreviation) FL.list)
               $ F.filterFrame (\r -> (F.rgetField @GT.StateFIPS r < 60)
                                 && not (F.rgetField @BR.OneDistrict r)
                                 && not (F.rgetField @GT.StateAbbreviation r `S.member` noMaps)
                               ) stateInfo
      planId sa = redistrictingPlanId sa "Passed" GT.Congressional
      planFiles sa = RedistrictingPlanFiles
        (bigDataPath <> "Census/cd" <> show mapYear <> "_ACS" <> show (ACS.tableYear acsTableYear) <> "/" <> sa <> ".csv")
        (draDataPath <> "districtStats/" <> show mapYear <> "/" <> sa <> "_congressional.csv")
      mapPair sa = (planId sa, planFiles sa)
  return $ M.fromList $ fmap mapPair states

allPassedSLDPlans :: (K.KnitEffects r, BRCC.CacheEffects r) => Int -> ACS.TableYear -> K.Sem r  (Map RedistrictingPlanId RedistrictingPlanFiles)
allPassedSLDPlans mapYear acsTableYear = do
  stateInfo <- K.ignoreCacheTimeM BR.stateAbbrCrosswalkLoader
  let statesAnd = FL.fold (FL.premap (\r -> (F.rgetField @GT.StateAbbreviation r, F.rgetField @BR.SLDUpperOnly r)) FL.list)
                  $ F.filterFrame (\r -> (F.rgetField @GT.StateFIPS r < 60)
                                         && not (F.rgetField @GT.StateAbbreviation r `S.member` S.insert "DC" noMaps)
                                  ) stateInfo
      planUpper sa = redistrictingPlanId sa "Passed" GT.StateUpper
      planUpperFiles sa = RedistrictingPlanFiles
                          (bigDataPath <> "Census/sldu" <> show mapYear <> "_ACS" <> show (ACS.tableYear acsTableYear) <> "/" <> sa <> ".csv")
                          (draDataPath <> "districtStats/" <> show mapYear <> "/" <> sa <> "_sldu.csv")
      mapPairUpper sa = (planUpper sa, planUpperFiles sa)
      planLower sa = redistrictingPlanId sa "Passed" GT.StateLower
      planLowerFiles sa = RedistrictingPlanFiles
                          (bigDataPath <> "Census/sldl" <> show mapYear <> "_ACS" <> show (ACS.tableYear acsTableYear) <> "/" <> sa <> ".csv")
                          (draDataPath <> "districtStats/" <> show mapYear <> "/" <> sa <> "_sldl.csv")
      mapPairLower sa = (planLower sa, planLowerFiles sa)
      mapPairs (sa, upperOnly) = mapPairUpper sa : if upperOnly then [] else [mapPairLower sa]
  return $ M.fromList $ concat $ fmap mapPairs statesAnd

redistrictingAnalysisCols :: Set FS.HeaderText
redistrictingAnalysisCols =
  S.fromList
  $ FS.HeaderText
  <$> ["NAME","TotalPop","DemPct","RepPct","TotalVAP","WhitePct","MinorityPct","HispanicPct","BlackPct","AsianPct","NativePct"]

redistrictingAnalysisRenames :: Map FS.HeaderText FS.ColTypeName
redistrictingAnalysisRenames = M.fromList [(FS.HeaderText "NAME", FS.ColTypeName "DistrictName")
                                          ,(FS.HeaderText "TotalPop", FS.ColTypeName "Population")
                                          ,(FS.HeaderText "TotalVAP", FS.ColTypeName "VAP")
--                                          ,(FS.HeaderText "DemPct", FS.ColTypeName "DemShare")
--                                          ,(FS.HeaderText "RepPct", FS.ColTypeName "RepShare")
--                                          ,(FS.HeaderText "Oth", FS.ColTypeName "OthShare")
                                          ,(FS.HeaderText "WhitePct", FS.ColTypeName "WhiteFrac")
                                          ,(FS.HeaderText "MinorityPct", FS.ColTypeName "MinorityFrac")
                                          ,(FS.HeaderText "HispanicPct", FS.ColTypeName "HispanicFrac")
                                          ,(FS.HeaderText "BlackPct", FS.ColTypeName "BlackFrac")
                                          ,(FS.HeaderText "AsianPct", FS.ColTypeName "AsianFrac")
                                          ,(FS.HeaderText "NativePct", FS.ColTypeName "NativeFrac")
                                          ]

redistrictingAnalysisCols' :: Set FS.HeaderText
redistrictingAnalysisCols' = S.fromList $ FS.HeaderText <$> ["ID","Total Pop","Dem","Rep","Oth","Total VAP","White","Minority","Hispanic","Black","Asian"]


redistrictingAnalysisRenames' :: Map FS.HeaderText FS.ColTypeName
redistrictingAnalysisRenames' = M.fromList [(FS.HeaderText "ID", FS.ColTypeName "DistrictName")
                                          ,(FS.HeaderText "Total Pop", FS.ColTypeName "Population")
                                          ,(FS.HeaderText "Total VAP", FS.ColTypeName "VAP")
                                          ,(FS.HeaderText "Dem", FS.ColTypeName "DemPct")
                                          ,(FS.HeaderText "Rep", FS.ColTypeName "RepPct")
                                          ,(FS.HeaderText "Oth", FS.ColTypeName "OthPct")
                                          ,(FS.HeaderText "White", FS.ColTypeName "WhiteFrac")
                                          ,(FS.HeaderText "Minority", FS.ColTypeName "MinorityFrac")
                                          ,(FS.HeaderText "Hispanic", FS.ColTypeName "HispanicFrac")
                                          ,(FS.HeaderText "Black", FS.ColTypeName "BlackFrac")
                                          ,(FS.HeaderText "Asian", FS.ColTypeName "AsianFrac")
                                          ]


-- this assumes these files are all like this one
redistrictingAnalysisRowGen :: FS.RowGen FS.DefaultStream 'FS.ColumnByName FCU.CommonColumns
redistrictingAnalysisRowGen = FS.modifyColumnSelector modF rg where
  rg = (FS.rowGen $ toString draDataPath <> "districtStats/2024/NY_congressional.csv") { FS.tablePrefix = ""
                                                                  , FS.separator = FS.CharSeparator ','
                                                                  , FS.rowTypeName = "DRAnalysisRaw"
                                                                  }
  modF = FS.renameSomeUsingNames redistrictingAnalysisRenames
         . FS.columnSubset redistrictingAnalysisCols
