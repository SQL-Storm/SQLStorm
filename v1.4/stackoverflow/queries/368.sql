-- {"query": "368.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14006} 
WITH
  VoteNet AS (
     SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
     FROM Votes
     GROUP BY PostId
  ),
  LinkCounts AS (
     SELECT PostId, COUNT(*) AS LinkCount
     FROM PostLinks
     GROUP BY PostId
  ),
  TagCountCte AS (
     SELECT Id AS PostId,
            CASE WHEN Tags IS NULL THEN 0
                 ELSE COALESCE(array_length(string_to_array(substring(Tags, 2, length(Tags)-2), '><'), 1), 0)
            END AS TagCount
     FROM Posts
  ),
  PostInfo AS (
     SELECT p.Id AS PostId,
            p.PostTypeId,
            p.Title,
            p.Tags,
            p.OwnerUserId,
            p.CreationDate,
            p.LastActivityDate,
            p.ViewCount,
            p.Score,
            p.Body,
            p.CommentCount,
            p.AcceptedAnswerId,
            COALESCE(v.NetVotes, 0) AS NetVotes,
            p.OwnerDisplayName,
            p.LastEditorUserId,
            p.LastEditorDisplayName,
            p.LastEditDate,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS TotalBadgesCorrelated,
            COALESCE(lc.LinkCount, 0) AS LinkCount,
            COALESCE(tc.TagCount, 0) AS TagCount
     FROM Posts p
     LEFT JOIN VoteNet v ON v.PostId = p.Id
     LEFT JOIN LinkCounts lc ON lc.PostId = p.Id
     LEFT JOIN TagCountCte tc ON tc.PostId = p.Id
  ),
  TypeRanked AS (
     SELECT *,
            ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY NetVotes DESC, ViewCount DESC, Score DESC) AS TypeRank
     FROM PostInfo
  ),
  SetA AS (
     SELECT * FROM TypeRanked
     WHERE PostTypeId = 1 AND NetVotes > 20 AND ViewCount > 1000
  ),
  SetB AS (
     SELECT * FROM TypeRanked
     WHERE PostTypeId = 2 AND NetVotes > -5
  ),
  Combined AS (
     SELECT * FROM SetA
     UNION ALL
     SELECT * FROM SetB
  )
SELECT
  PostId,
  Title,
  PostTypeId,
  OwnerUserId,
  OwnerDisplayName,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Score,
  NetVotes,
  GoldBadges,
  TotalBadgesCorrelated,
  TagCount,
  LinkCount,
  TypeRank
FROM Combined
ORDER BY PostTypeId, TypeRank
LIMIT 200;