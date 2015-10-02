{-#LANGUAGE OverloadedStrings #-}
module Servant.JS.Internal
  ( JavaScriptGenerator
  , CommonGeneratorOptions(..)
  , defCommonGeneratorOptions
  , AjaxReq
  , jsSegments
  , segmentToStr
  , segmentTypeToStr
  , jsParams
  , jsGParams
  , jsMParams
  , paramToStr
  , toValidFunctionName
  , toJSHeader
  -- re-exports
  , (:<|>)(..)
  , (:>)
  , defReq
  , reqHeaders
  , HasForeign(..)
  , HeaderArg(..)
  , concatCase
  , snakeCase
  , camelCase
  , ReqBody
  , JSON
  , FormUrlEncoded
  , Post
  , Get
  , Raw
  , Header
  ) where

import           Control.Lens                  ((^.))
import qualified Data.CharSet as Set
import qualified Data.CharSet.Unicode.Category as Set
import           Data.Monoid
import qualified Data.Text as T
import           Data.Text (Text)
import           Servant.Foreign

type AjaxReq = Req

-- A 'JavascriptGenerator' just takes the data found in the API type
-- for each endpoint and generates Javascript code in a Text. Several
-- generators are available in this package.
type JavaScriptGenerator = [Req] -> Text

-- | This structure is used by specific implementations to let you
-- customize the output
data CommonGeneratorOptions = CommonGeneratorOptions
  {
    functionNameBuilder :: FunctionName -> Text  -- ^ function generating function names
  , requestBody :: Text                -- ^ name used when a user want to send the request body (to let you redefine it)
  , successCallback :: Text            -- ^ name of the callback parameter when the request was successful
  , errorCallback :: Text              -- ^ name of the callback parameter when the request reported an error
  , moduleName :: Text                 -- ^ namespace on which we define the foreign function (empty mean local var)
  , urlPrefix :: Text                  -- ^ a prefix we should add to the Url in the codegen
  }

-- | Default options.
--
-- @
-- > defCommonGeneratorOptions = CommonGeneratorOptions
-- >   { functionNameBuilder = camelCase
-- >   , requestBody = "body"
-- >   , successCallback = "onSuccess"
-- >   , errorCallback = "onError"
-- >   , moduleName = ""
-- >   , urlPrefix = ""
-- >   }
-- @
defCommonGeneratorOptions :: CommonGeneratorOptions
defCommonGeneratorOptions = CommonGeneratorOptions
  {
    functionNameBuilder = camelCase
  , requestBody = "body"
  , successCallback = "onSuccess"
  , errorCallback = "onError"
  , moduleName = ""
  , urlPrefix = ""
  }

-- | Attempts to reduce the function name provided to that allowed by @'Foreign'@.
--
-- https://mathiasbynens.be/notes/javascript-identifiers
-- Couldn't work out how to handle zero-width characters.
--
-- @TODO: specify better default function name, or throw error?
toValidFunctionName :: Text -> Text
-- @TODO: Cons text
--

toValidFunctionName t =
  case T.uncons t of
    Just (x,xs) ->
      setFirstChar x `T.cons` T.filter remainder xs 
    Nothing -> "_"
  where
    setFirstChar c = if firstChar c then c else '_'
    firstChar c = prefixOK c || any (Set.member c) firstLetterOK
    remainder c = prefixOK c || any (Set.member c) remainderOK
    -- Valid prefixes
    prefixOK c = c `elem` ['$','_']
    -- Unicode character sets
    firstLetterOK = [ Set.lowercaseLetter
                    , Set.uppercaseLetter
                    , Set.titlecaseLetter
                    , Set.modifierLetter
                    , Set.otherLetter
                    , Set.letterNumber ]
    remainderOK   = firstLetterOK
               <> [ Set.nonSpacingMark
                  , Set.spacingCombiningMark
                  , Set.decimalNumber
                  , Set.connectorPunctuation ]
{-
toValidFunctionName (x:xs) = [setFirstChar x] <> filter remainder xs
  where
    setFirstChar c = if firstChar c then c else '_'
    firstChar c = prefixOK c || any (Set.member c) firstLetterOK
    remainder c = prefixOK c || any (Set.member c) remainderOK
    -- Valid prefixes
    prefixOK c = c `elem` ['$','_']
    -- Unicode character sets
    firstLetterOK = [ Set.lowercaseLetter
                    , Set.uppercaseLetter
                    , Set.titlecaseLetter
                    , Set.modifierLetter
                    , Set.otherLetter
                    , Set.letterNumber ]
    remainderOK   = firstLetterOK
               <> [ Set.nonSpacingMark
                  , Set.spacingCombiningMark
                  , Set.decimalNumber
                  , Set.connectorPunctuation ]
toValidFunctionName [] = "_"
-}

toJSHeader :: HeaderArg -> Text
toJSHeader (HeaderArg n)          = toValidFunctionName ("header" <> n)
toJSHeader (ReplaceHeaderArg n p)
  | pn `T.isPrefixOf` p = pv <> " + \"" <> rp <> "\""
  | pn `T.isSuffixOf` p = "\"" <> rp <> "\" + " <> pv
  | pn `T.isInfixOf` p  = "\"" <> (T.replace pn ("\" + " <> pv <> " + \"") p)
                             <> "\""
  | otherwise         = p
  where
    pv = toValidFunctionName ("header" <> n)
    pn = "{" <> n <> "}"
    rp = T.replace pn "" p

jsSegments :: [Segment] -> Text
jsSegments []  = ""
jsSegments [x] = "/" <> segmentToStr x False
jsSegments (x:xs) = "/" <> segmentToStr x True <> jsSegments xs

segmentToStr :: Segment -> Bool -> Text
segmentToStr (Segment st ms) notTheEnd =
  segmentTypeToStr st <> jsMParams ms <> if notTheEnd then "" else "'"

segmentTypeToStr :: SegmentType -> Text
segmentTypeToStr (Static s) = s
segmentTypeToStr (Cap s)    = "' + encodeURIComponent(" <> s <> ") + '"

jsGParams :: Text -> [QueryArg] -> Text
jsGParams _ []     = ""
jsGParams _ [x]    = paramToStr x False
jsGParams s (x:xs) = paramToStr x True <> s <> jsGParams s xs

jsParams :: [QueryArg] -> Text
jsParams = jsGParams "&"

jsMParams :: [MatrixArg] -> Text
jsMParams [] = ""
jsMParams xs = ";" <> jsGParams ";" xs

paramToStr :: QueryArg -> Bool -> Text
paramToStr qarg notTheEnd =
  case qarg ^. argType of
    Normal -> name
           <> "=' + encodeURIComponent("
           <> name
           <> if notTheEnd then ") + '" else ")"
    Flag   -> name <> "="
    List   -> name
           <> "[]=' + encodeURIComponent("
           <> name
           <> if notTheEnd then ") + '" else ")"
  where name = qarg ^. argName
