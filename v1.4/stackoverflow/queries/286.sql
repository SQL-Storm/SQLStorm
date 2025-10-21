WITH
RecentPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    COALESCE(u.DisplayName, 'unknown') AS OwnerName,
    p.OwnerUserId AS OwnerUserId,
    COALESCE(u.Reputation, 0) AS Reputation,
    p.PostTypeId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS TypeRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountFromSub
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days')
    AND p.PostTypeId IN (1, 2)
),
ParsedTags AS (
  SELECT rp.PostId,
         UNNEST(string_to_array(substr(rp.Tags, 2, length(rp.Tags) - 2), '><')) AS TagName
  FROM RecentPosts rp
),
QueryA AS (
  SELECT rp.PostId,
         rp.Title,
         rp.CreationDate,
         rp.LastActivityDate,
         rp.Score,
         rp.ViewCount,
         rp.OwnerName,
         rp.OwnerUserId,
         rp.Reputation,
         rp.PostTypeId,
         CASE WHEN rp.ViewCount > 0 THEN (rp.Score * 1.0) / rp.ViewCount ELSE NULL END AS ScorePerView,
         rp.OwnerName || ' [' || CAST(rp.Reputation AS TEXT) || ']' AS OwnerDisplay,
         rp.TypeRank,
         rp.CommentCountFromSub AS CommentCountCorrelated,
         NULL AS Extra
  FROM RecentPosts rp
  JOIN ParsedTags pt ON pt.PostId = rp.PostId
  WHERE (rp.Score > 100 OR rp.ViewCount > 1000 OR rp.TypeRank <= 5)
    AND EXISTS (SELECT 1 FROM ParsedTags t2 WHERE t2.PostId = rp.PostId)
  GROUP BY rp.PostId, rp.Title, rp.CreationDate, rp.LastActivityDate, rp.Score, rp.ViewCount,
           rp.OwnerName, rp.OwnerUserId, rp.Reputation, rp.PostTypeId, rp.TypeRank, rp.CommentCountFromSub
),
QueryB AS (
  SELECT NULL::INTEGER AS PostId,
         NULL::TEXT AS Title,
         NULL::TIMESTAMP WITHOUT TIME ZONE AS CreationDate,
         NULL::TIMESTAMP WITHOUT TIME ZONE AS LastActivityDate,
         NULL::INTEGER AS Score,
         NULL::INTEGER AS ViewCount,
         t.UserName AS OwnerName,
         t.UserId AS OwnerUserId,
         t.Reputation,
         NULL::INTEGER AS PostTypeId,
         NULL::NUMERIC AS ScorePerView,
         NULL AS OwnerDisplay,
         NULL AS TypeRank,
         NULL AS CommentCountCorrelated,
         'From heavy-user activity (union)' AS Extra
  FROM (
     SELECT u.Id AS UserId,
            COALESCE(u.DisplayName, 'anonymous') AS UserName,
            COALESCE(u.Reputation, 0) AS Reputation
     FROM Posts p
     LEFT JOIN Users u ON p.OwnerUserId = u.Id
     GROUP BY u.Id, u.DisplayName, u.Reputation
     HAVING COUNT(*) > 10
  ) t
)
SELECT *
FROM (
  SELECT PostId, Title, CreationDate, LastActivityDate, Score, ViewCount, OwnerName, OwnerUserId, Reputation, PostTypeId, ScorePerView, OwnerDisplay, TypeRank, CommentCountCorrelated, Extra
  FROM QueryA
  UNION ALL
  SELECT PostId, Title, CreationDate, LastActivityDate, Score, ViewCount, OwnerName, OwnerUserId, Reputation, PostTypeId, ScorePerView, OwnerDisplay, TypeRank, CommentCountCorrelated, Extra
  FROM QueryB
) AS combined
ORDER BY COALESCE(Score, 0) DESC NULLS LAST
LIMIT 100;