{-
    Notifaika reposts notifications
    from different feeds to Gitter chats.
    Copyright (C) 2015 Yuriy Syrovetskiy

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
-}

{-# LANGUAGE NamedFieldPuns #-}

module Notifaika.Discourse where

import Notifaika.Types

import            Control.Eff
import            Control.Eff.Lift
import            Control.Lens
import            Data.Aeson
import            Data.Aeson.TH
import            Data.IntMap   as IntMap
import            Data.Monoid
import            Data.String.X
import            Data.Text     ( Text )
import qualified  Data.Text     as Text
import            Network.Wreq  as Wreq

data User = User { user_id :: Int, user_username :: Text }

deriveJSON defaultOptions{fieldLabelModifier = dropPrefix "user_"} ''User

data Poster = Poster { poster_user_id :: Int }
    deriving (Eq, Show)

deriveJSON defaultOptions{fieldLabelModifier = dropPrefix "poster_"} ''Poster

data Topic = Topic  { topic_fancy_title :: Text
                    , topic_id :: Integer
                    , topic_posters :: [Poster]
                    , topic_slug :: Text
                    }
    deriving (Eq, Show)

deriveJSON defaultOptions{fieldLabelModifier = dropPrefix "topic_"} ''Topic

data TopicList = TopicList { topicList_topics :: [Topic] }

deriveJSON  defaultOptions{fieldLabelModifier = dropPrefix "topicList_"}
            ''TopicList

data Latest = Latest { latest_topic_list :: TopicList, latest_users :: [User] }

deriveJSON defaultOptions{fieldLabelModifier = dropPrefix "latest_"} ''Latest

resultToEither :: Result a -> Either String a
resultToEither (Success s)  = Right s
resultToEither (Error e)    = Left e

getDiscourseEvents :: (SetMember Lift (Lift IO) r) => Url -> Eff r [Event]
getDiscourseEvents baseUrl = do
    let url = baseUrl <> "/latest.json"
    jsonResponse <- lift $ do
      response <- Wreq.get url
      asJSON response -- XXX: because 'asJSON' require MonadThrow
    return . extractEvents baseUrl $ jsonResponse ^. responseBody

extractEvents :: Url -> Latest -> [Event]
extractEvents baseUrl latest =
    let Latest{latest_topic_list=TopicList{topicList_topics}, latest_users} =
            latest
        users = IntMap.fromList [ (user_id, user_username)
                                | User{user_id, user_username} <- latest_users
                                ]
    in  [ Event{eventId, message}
        | Topic{topic_fancy_title, topic_id, topic_posters, topic_slug}
              <- topicList_topics
        , let link = mconcat  [ Text.pack baseUrl
                              , "/t/", topic_slug, "/", showText topic_id ]
              Poster{poster_user_id} = head topic_posters
              eventId = Eid (showText topic_id)
              message = mconcat [ users ! poster_user_id
                                , " опубликовал на форуме тему «"
                                , topic_fancy_title, "»\n", link ]
        ]

showText :: Show a => a -> Text
showText = Text.pack . show
