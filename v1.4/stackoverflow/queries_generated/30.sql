-- {"query": "30.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 889} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    -- derived metrics
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount * 0.5 + COALESCE(p.FavoriteCount,0) * 2 +
        DATEDIFF(second, p.CreationDate, GETDATE()) * -0.0001
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
TopQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount
  FROM RankedPosts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 AND p.rn <= 50
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Posts p
  CROSS APPLY (
    SELECT value AS TagName
    FROM string_split(REPLACE(REPLACE(p.Tags, '<',''), '>', ''), ',')
  ) AS T
  GROUP BY t.TagName
),
ActivityWindow AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    DATEDIFF(day, p.CreationDate, GETDATE()) AS AgeDays,
    CASE
      WHEN p.ViewCount > 1000 THEN 'HighTraffic'
      WHEN p.ViewCount > 100 THEN 'MediumTraffic'
      ELSE 'LowTraffic'
    END AS TrafficBucket
  FROM Posts p
  WHERE p.LastActivityDate > DATEADD(day, -7, GETDATE())
),
ComplexJoins AS (
  SELECT
    q.Id AS QuestionId,
    a.Id AS AnswerId,
    c.Id AS CommentId,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate,
    vl.Name AS VoteTypeName
  FROM TopQuestions q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN Votes v ON v.PostId IN (q.Id, a.Id)
  LEFT JOIN VoteTypes vl ON v.VoteTypeId = vl.Id
  WHERE v.CreationDate > DATEADD(day, -30, GETDATE())
)
SELECT
  tq.Id AS QuestionId,
  tq.Title,
  tq.OwnerDisplayName,
  tq.CreationDate AS QuestionCreated,
  tq.LastActivityDate AS LastActive,
  tq.ViewCount,
  tq.Score,
  ts.PostCount AS TaggedQuestionCount,
  ts.AvgScore AS TaggedQuestionAvgScore,
  at.MaxViews AS MaxTagView,
  aw.AgeDays,
  aw.TrafficBucket,
  ca.TotalComments,
  ca.TotalVotes
FROM TopQuestions tq
LEFT JOIN TagStats ts ON 1=1
LEFT JOIN ActivityWindow aw ON aw.Id = tq.Id
LEFT JOIN (
  SELECT
    p.Id,
    COUNT(*) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalVotes
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
) ca ON ca.Id = tq.Id
ORDER BY tq.CreationDate DESC
OPTION (HASH JOIN);