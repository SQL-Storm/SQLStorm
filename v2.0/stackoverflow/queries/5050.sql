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
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
tag_burst AS (
  SELECT
    tposts.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS TagName,
      p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
  ) AS tposts
  JOIN Posts p ON p.Id = tposts.PostId
  GROUP BY tposts.TagName
  HAVING COUNT(*) > 5
),
activity_by_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT v.PostId) AS VotesCast,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName
)
SELECT
  rq.PostId AS QuestionId,
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
) aq ON rq.PostId = aq.Id
LEFT JOIN (
  SELECT
    tb2.TagName,
    tb2.PostCount,
    tb2.AvgScore
  FROM (
    SELECT
      tposts.TagName,
      COUNT(*) AS PostCount,
      AVG(p.Score) AS AvgScore
    FROM (
      SELECT
        unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS TagName,
        p.Id AS PostId
      FROM Posts p
      WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    ) AS tposts
    JOIN Posts p ON p.Id = tposts.PostId
    GROUP BY tposts.TagName
    HAVING COUNT(*) > 5
  ) tb2
  ORDER BY tb2.PostCount DESC
  LIMIT 1
) tb ON TRUE
LEFT JOIN activity_by_user aau ON rq.OwnerUserId = aau.UserId
ORDER BY rq.CreationDate DESC
LIMIT 100;