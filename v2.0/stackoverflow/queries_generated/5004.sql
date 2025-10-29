-- {"query": "5004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 580} 
WITH
ActivePosts AS (
  SELECT p.Id,
         p.PostTypeId,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.LastActivityDate,
         p.Title,
         p.Tags,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers for benchmarking diversity
),
TagStats AS (
  SELECT t.TagName,
         COUNT(*) AS TagPostCount,
         AVG(p.Score) AS AvgScore,
         SUM(p.ViewCount) AS TotalViews
  FROM ActivePosts ap
  CROSS APPLY (SELECT value AS TagName
               FROM string_split(ap.Tags, '><')
               WHERE value <> '') s
  JOIN Tags t ON t.TagName = s.value
  JOIN Posts p ON p.Id = ap.Id
  GROUP BY t.TagName
),
TopTags AS (
  SELECT TagName,
         TagPostCount,
         AvgScore,
         TotalViews,
         ROW_NUMBER() OVER (ORDER BY TagPostCount DESC, AvgScore DESC) AS rn
  FROM TagStats
)
SELECT
  a.Id AS PostId,
  a.PostTypeId,
  a.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  a.Title,
  a.Tags,
  a.Score,
  a.ViewCount,
  a.CreationDate,
  a.LastActivityDate,
  a.AnswerCount,
  a.CommentCount,
  a.FavoriteCount,
  COALESCE(vt.VoteCount, 0) AS VoteCount,
  vb.TotalBadges,
  tg.TagName,
  s.AvgScore AS TagAvgScore,
  s.TotalViews AS TagTotalViews
FROM ActivePosts a
LEFT JOIN Users u ON a.OwnerUserId = u.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS VoteCount
  FROM Votes
  WHERE VoteTypeId IN (2,3) -- UpMod and DownMod for signal
  GROUP BY PostId
) vt ON a.Id = vt.PostId
LEFT JOIN (
  SELECT UserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY UserId
) vb ON a.OwnerUserId = vb.UserId
LEFT JOIN (
  SELECT TagName
  FROM TopTags tt
  WHERE tt.rn = 1
) tg ON tg.TagName IS NOT NULL
LEFT JOIN (
  SELECT tt.TagName, tt.TagPostCount, tt.AvgScore, tt.TotalViews
  FROM TopTags tt
  WHERE tt.rn = 1
) s ON s.TagName = tg.TagName
ORDER BY a.CreationDate DESC
LIMIT 100;