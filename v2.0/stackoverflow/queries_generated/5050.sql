-- {"query": "5050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 619} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_burst AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
  ) AS tposts
  JOIN Posts p ON p.Id = tposts.PostId
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
activity_by_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(DISTINCT v.PostId) AS VotesCast,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName
)
SELECT
  rq.Id AS QuestionId,
  rq.Title,
  rq.Tags,
  rq.CreationDate AS CreatedAt,
  rq.Score,
  rq.ViewCount,
  rq.OwnerUserId AS OwnerId,
  aq.TotalViews,
  tb.TagName AS TopTag,
  tb.PostCount,
  tb.AvgScore,
  aau.UserId AS ActiveUserId,
  aau.DisplayName AS ActiveUserName,
  aau.Questions AS UserQuestions,
  aau.VotesCast AS UserVotesCast,
  aau.LastActive AS UserLastActivity
FROM recent_questions rq
LEFT JOIN (
  SELECT p.Id, p.ViewCount AS TotalViews
  FROM Posts p
) aq ON rq.Id = aq.Id
LEFT JOIN (
  SELECT
    t.TagName,
    MAX(t.PostCount) AS PostCount,
    MAX(t.AvgScore) AS AvgScore
  FROM tag_burst t
  GROUP BY t.TagName
  ORDER BY t.PostCount DESC
  LIMIT 1
) tb ON TRUE
LEFT JOIN activity_by_user aau ON rq.OwnerUserId = aau.UserId
ORDER BY rq.CreationDate DESC
LIMIT 100;