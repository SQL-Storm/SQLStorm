-- {"query": "211.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8141} 
WITH RankedPosts AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.PostTypeId,
         p.OwnerUserId,
         p.CreationDate,
         p.LastActivityDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.OwnerDisplayName
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    AND p.PostTypeId IN (1, 2)
),
TagExtraction AS (
  SELECT rp.PostId,
         t.TagName
  FROM RankedPosts rp
  CROSS JOIN LATERAL UNNEST(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '><')) AS t(TagName)
),
TagCounts AS (
  SELECT PostId, COUNT(*) AS TagCount
  FROM TagExtraction
  GROUP BY PostId
),
CommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
UserInfo AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation
  FROM Users u
),
Combined AS (
  SELECT rp.PostId,
         rp.Title,
         rp.PostTypeId,
         rp.OwnerUserId,
         rp.CreationDate,
         rp.LastActivityDate,
         rp.Score,
         rp.ViewCount,
         COALESCE(cc.CommentCount, 0) AS CommentCount,
         COALESCE(tc.TagCount, 0) AS TagCount,
         COALESCE(ui.DisplayName, rp.OwnerDisplayName) AS OwnerDisplayName,
         COALESCE(ui.Reputation, 0) AS OwnerReputation,
         (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = rp.OwnerUserId) AS OwnerAvgPostScore,
         ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.LastActivityDate DESC) AS rank,
         MAX(COALESCE(cc.CommentCount, 0)) OVER () AS GlobalMaxComment
  FROM RankedPosts rp
  LEFT JOIN CommentCounts cc ON cc.PostId = rp.PostId
  LEFT JOIN TagCounts tc ON tc.PostId = rp.PostId
  LEFT JOIN Users ui ON ui.Id = rp.OwnerUserId
)
SELECT *
FROM (
  SELECT * FROM Combined WHERE rank <= 60
  UNION ALL
  SELECT * FROM Combined WHERE CommentCount = GlobalMaxComment
) AS FinalSet
ORDER BY rank
LIMIT 200;