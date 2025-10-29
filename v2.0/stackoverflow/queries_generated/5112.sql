-- {"query": "5112.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 641} 
WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    COALESCE(v.BountyAmount,0) AS BountyAmount
  FROM Posts p
  LEFT JOIN Votes v
    ON p.Id = v.PostId AND v.VoteTypeId = 8  -- BountyStart
  WHERE p.PostTypeId = 1
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount
  FROM Tags t
  GROUP BY t.TagName
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.ProfileImageUrl,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
  FROM Users u
)
SELECT
  rq.PostId,
  rq.Title,
  rq.OwnerUserId,
  rq.CreationDate AS QuestionCreationDate,
  rq.LastActivityDate,
  rq.Score AS QuestionScore,
  rq.ViewCount,
  rq.AnswerCount,
  ra.BountyAmount,
  ui.DisplayName AS OwnerDisplayName,
  ui.Reputation AS OwnerReputation,
  COALESCE(JSON_ARRAYAGG(JSON_OBJECT(
        'Tag', t.TagName,
        'Count', tp.TagCount
      )) FILTER (WHERE t.TagName IS NOT NULL), '[]') AS TagStats,
  JSON_BUILD_OBJECT(
    'MostActiveUser', (
      SELECT DisplayName
      FROM Users
      WHERE Id = rq.OwnerUserId
      LIMIT 1
    ),
    'RecentActivity', (
      SELECT MAX(la.LastActivityDate)
      FROM RecentActivity la
      WHERE la.PostId = rq.PostId
    )
  ) AS Meta
FROM TopQuestions rq
LEFT JOIN RecentActivity ra
  ON rq.PostId = ra.PostId
LEFT JOIN UserStats ui
  ON rq.OwnerUserId = ui.UserId
LEFT JOIN Tags t
  ON t.Id IN (
       SELECT UNNEST(string_to_array(REPLACE(REPLACE(rq.Tags, '<',''), '>', ''), ','))
  )
LEFT JOIN TagPopularity tp
  ON tp.TagName = t.TagName
WHERE rq.CreationDate >= NOW() - INTERVAL '30 days'
ORDER BY rq.Score DESC, rq.ViewCount DESC
LIMIT 100;