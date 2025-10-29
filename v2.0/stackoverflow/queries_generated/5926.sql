-- {"query": "5926.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 803} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC NULLS LAST,
        p.ViewCount DESC NULLS LAST,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
TopQ AS (
  SELECT *
  FROM RankedPosts
  WHERE PostTypeId = 1 AND rn = 1
),
TopA AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId,
    a.Title AS AnswerTitle,
    a.CreationDate AS AnswerDate,
    a.Score AS AnswerScore,
    a.OwnerUserId AS AnswerOwner,
    a.LastActivityDate AS AnswerLastActivity,
    u.DisplayName AS OwnerDisplayName
  FROM RankedPosts a
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2
    AND a.ParentId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
),
TagPopularity AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TotalTagCount
  FROM Tags t
  GROUP BY t.TagName
),
ActivityWindow AS (
  SELECT
    p.PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    TIMESTAMPADD(MINUTE, 0, p.LastActivityDate) AS LastActivityNormalized
  FROM RankedPosts p
  WHERE p.rn = 1
),
CrossQuery AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.ViewCount,
    w.Score,
    w.Tags,
    w.LastActivityNormalized,
    ta.TotalTagCount,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = w.PostId
          AND v.VoteTypeId IN (2,4)
      ) THEN 1 ELSE 0
    END AS HasUpOrBadVote
  FROM ActivityWindow w
  LEFT JOIN TagPopularity ta ON ta.TagName = (
    SELECT unnest(string_to_array(substring(w.Tags, 2, length(w.Tags)-2), '><')) LIMIT 1
  )
  WHERE w.Score > 0
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.LastActivityNormalized,
  c.TotalTagCount,
  c.HasUpOrBadVote,
  u.DisplayName AS OwnerDisplay,
  a.AnswerId,
  a.ParentId AS QuestionId,
  a.AnswerDate,
  a.AnswerScore,
  a.OwnerDisplayName
FROM CrossQuery c
LEFT JOIN Users u ON c.PostId = u.Id
LEFT JOIN TopA a ON a.ParentId = c.PostId
UNION ALL
SELECT
  tq.PostId,
  tq.Title,
  tq.CreationDate,
  tq.ViewCount,
  tq.Score,
  tq.LastActivityDate,
  tq.TotalTagCount,
  tq.HasUpOrBadVote,
  uq.DisplayName AS OwnerDisplay,
  NULL AS AnswerId,
  NULL AS QuestionId,
  NULL AS AnswerDate,
  NULL AS AnswerScore,
  NULL AS AnswerOwner
FROM TopQ tq
LEFT JOIN Users uq ON tq.OwnerUserId = uq.Id
ORDER BY CreationDate DESC
LIMIT 100;