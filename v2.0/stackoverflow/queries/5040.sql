WITH
recent_questions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Tags,
         p.CreationDate,
         p.OwnerUserId,
         p.ViewCount,
         p.Score,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         p.LastActivityDate,
         p.LastEditorUserId,
         p.LastEditDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
tag_activity AS (
  SELECT tag AS TagName,
         COUNT(*) AS QuestionCount,
         SUM(p.ViewCount) AS TotalViews,
         SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  ) t
  GROUP BY tag
),
top_tags AS (
  SELECT TagName,
         QuestionCount,
         TotalViews,
         TotalScore,
         RANK() OVER (ORDER BY TotalViews DESC, TotalScore DESC) AS tag_rank
  FROM tag_activity
)
SELECT
  rq.PostId,
  rq.Title,
  rq.CreationDate,
  rq.OwnerUserId,
  rq.ViewCount,
  rq.Score,
  rq.AnswerCount,
  rq.CommentCount,
  rq.FavoriteCount,
  rq.LastActivityDate,
  rq.LastEditDate,
  tou.DisplayName AS OwnerDisplayName,
  COALESCE(vt.UpModCount, 0) AS UpVotesOnQuestion,
  COALESCE(vt2.DownModCount, 0) AS DownVotesOnQuestion,
  COALESCE(tb2.BadgeCount, 0) AS GoldBadgesForOwner,
  tt.tag_rank
FROM recent_questions rq
LEFT JOIN Users tou ON rq.OwnerUserId = tou.Id
LEFT JOIN (
  SELECT v.PostId, COUNT(*) AS UpModCount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE vt.Name = 'UpMod'
  GROUP BY v.PostId
) vt ON rq.PostId = vt.PostId
LEFT JOIN (
  SELECT v.PostId, COUNT(*) AS DownModCount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE vt.Name = 'DownMod'
  GROUP BY v.PostId
) vt2 ON rq.PostId = vt2.PostId
LEFT JOIN (
  SELECT b.UserId, COUNT(*) AS BadgeCount
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
) tb2 ON rq.OwnerUserId = tb2.UserId
LEFT JOIN (
  SELECT TagName, tag_rank
  FROM top_tags
  ORDER BY tag_rank
  LIMIT 10
) tt ON 1=1
WHERE tt.tag_rank = 1
ORDER BY rq.CreationDate DESC
LIMIT 100;