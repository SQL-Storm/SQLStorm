-- {"query": "5875.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 957} 
WITH TopTaggedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    t.TagName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.ViewCount DESC, p.Score DESC) AS rn
  FROM Posts p
  JOIN Tags ta ON ta.Id = p.Tags::int  -- placeholder cast to simulate tag linkage in this schema
  JOIN UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON true
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_user
  FROM Posts p
  WHERE p.PostTypeId = 1
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
CrossReference AS (
  SELECT
    v1.PostId,
    v1.UserId AS VoterId,
    v1.CreationDate AS VoteDate,
    v1.VoteTypeId,
    vt.Name AS VoteTypeName
  FROM Votes v1
  JOIN VoteTypes vt ON vt.Id = v1.VoteTypeId
  WHERE v1.VoteTypeId IN (2,3,6,10,11,16) -- Upvote/Downvote/Close/Deletion/Undeletion/ModeratorReview (for benchmarking variety)
),
ComplexExpression AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    (p.Score * 1.0) / NULLIF(p.ViewCount, 0) AS ScorePerView,
    (EXTRACT(epoch FROM p.LastActivityDate - p.CreationDate) / 3600) AS HoursActive,
    CASE
      WHEN p.ViewCount > 1000 THEN 'HighVisibility'
      WHEN p.ViewCount > 100 THEN 'Medium'
      ELSE 'Low'
    END AS VisibilityBand
  FROM Posts p
  WHERE p.PostTypeId = 1
),
AggMetrics AS (
  SELECT
    t.TagName,
    COUNT(*) AS QCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM TopTaggedQuestions t
  JOIN Posts p ON p.Id = t.PostId
  WHERE t.rn = 1
  GROUP BY t.TagName
),
FinalEnvelope AS (
  SELECT
    qu.Id AS QuestionId,
    qu.Title AS QuestionTitle,
    qu.OwnerUserId,
    ru.DisplayName AS OwnerDisplayName,
    ru.Reputation,
    cr.VoteDate,
    cr.VoteTypeName,
    ce.ScorePerView,
    ce.HoursActive,
    ce.VisibilityBand,
    am.QCount AS RelatedQuestionsForTag,
    am.AvgScore,
    am.TotalViews
  FROM Posts qu
  LEFT JOIN UserStats ru ON ru.UserId = qu.OwnerUserId
  LEFT JOIN CrossReference cr ON cr.PostId = qu.Id
  LEFT JOIN ComplexExpression ce ON ce.Id = qu.Id
  LEFT JOIN AggMetrics am ON am.TagName = SUBSTRING(qu.Tags, 2, LENGTH(qu.Tags)-2) -- rough tag mapping
  WHERE qu.PostTypeId = 1
    AND qu.ClosedDate IS NULL
)
SELECT
  FE.QuestionId,
  FE.QuestionTitle,
  FE.OwnerDisplayName,
  FE.Reputation,
  FE.VoteDate,
  FE.VoteTypeName,
  FE.ScorePerView,
  FE.HoursActive,
  FE.VisibilityBand,
  FE.RelatedQuestionsForTag,
  FE.AvgScore,
  FE.TotalViews
FROM FinalEnvelope FE
WHERE FE.TotalViews > 500
ORDER BY FE.TotalViews DESC, FE.ScorePerView DESC
LIMIT 100;