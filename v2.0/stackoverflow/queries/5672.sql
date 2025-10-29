-- {"query": "5672.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 610}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
top_owners AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) AS QuestionCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.ViewCount) AS AvgViews
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(*) >= 5
),
tag_exploded AS (
  SELECT
    rt.PostId,
    tag AS Tag
  FROM Posts p
  JOIN recent_questions rt ON rt.PostId = p.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(
      -- remove leading '<' and trailing '>' if present
      CASE
        WHEN p.Tags LIKE '<%' THEN
          CASE
            WHEN p.Tags LIKE '%>' THEN substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2)
            ELSE substring(p.Tags FROM 2)
          END
        ELSE p.Tags
      END
    , '><')) AS tag
  ) t
  WHERE p.Tags IS NOT NULL
),
tag_metrics AS (
  SELECT
    te.Tag AS TagName,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS TotalScore
  FROM tag_exploded te
  JOIN Posts p ON p.Id = te.PostId
  GROUP BY te.Tag
),
correlated_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate AS QuestionDate,
    o.DisplayName AS OwnerName,
    COALESCE(vn.VoteCount, 0) AS VoteCount
  FROM recent_questions q
  LEFT JOIN Users o ON o.Id = q.OwnerUserId
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
      AND CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
    GROUP BY PostId
  ) vn ON vn.PostId = q.PostId
),
complex_filter AS (
  SELECT
    ca.PostId,
    ca.Title,
    ca.QuestionDate,
    ca.OwnerName,
    ca.VoteCount,
    tm.TagName
  FROM correlated_activity ca
  LEFT JOIN tag_metrics tm ON true
  WHERE ca.QuestionDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '60 days'
    OR ca.VoteCount > 0
)
SELECT
  rf.PostId,
  rf.Title,
  rf.QuestionDate,
  rf.OwnerName,
  rf.VoteCount,
  rf.TagName,
  ro.QuestionCount AS OwnerQuestionCount,
  ro.ScoreSum AS OwnerScoreSum,
  ro.AvgViews AS OwnerAvgViews
FROM complex_filter rf
LEFT JOIN top_owners ro
  ON ro.UserId = (
    SELECT p2.OwnerUserId
    FROM Posts p2
    WHERE p2.Id = rf.PostId
    LIMIT 1
  )
ORDER BY rf.QuestionDate DESC
LIMIT 100;