-- {"query": "5133.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 626} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    p.FavoriteCount,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate IS NOT NULL
),
TopActiveOwners AS (
  SELECT
    r.OwnerUserId,
    r.DisplayName,
    r.Reputation,
    r.Location,
    r.AccountId,
    COUNT(*) AS QuestionsOpened,
    AVG(r.Score) AS AvgScore,
    SUM(r.ViewCount) AS TotalViews,
    MAX(r.LastActivityDate) AS LastActiveQuestion
  FROM RankedPosts r
  WHERE r.rn_owner = 1
  GROUP BY r.OwnerUserId, r.DisplayName, r.Reputation, r.Location, r.AccountId
),
RecentTagInteractions AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) AS AvgUpvotesPerQuestion,
    MAX(p.LastActivityDate) AS LastQuestionActivity
  FROM Posts p
  CROSS APPLY (
    SELECT TOP 1 value AS TagName
    FROM string_split(p.Tags, '><')
  ) AS t
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
CrossJoined AS (
  SELECT
    o.OwnerUserId,
    o.DisplayName AS OwnerDisplayName,
    o.Reputation,
    o.Location,
    o.TotalViews,
    o.LastActiveQuestion,
    t.TagQuestionCount,
    t.AvgUpvotesPerQuestion,
    t.LastQuestionActivity
  FROM TopActiveOwners o
  LEFT JOIN (
    SELECT 1 AS dummy, 0 AS TagQuestionCount
  ) z ON 1=0
  LEFT JOIN RecentTagInteractions t ON 1=1
)
SELECT
  cu.OwnerUserId,
  cu.OwnerDisplayName,
  cu.Reputation,
  cu.Location,
  cu.TotalViews,
  cu.LastActiveQuestion,
  cu.TagQuestionCount,
  cu.AvgUpvotesPerQuestion,
  cu.LastQuestionActivity
FROM CrossJoined cu
ORDER BY cu.Reputation DESC, cu.TotalViews DESC
LIMIT 100;