-- {"query": "5466.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 543} 
WITH RecentLikes AS (
  SELECT
    v.PostId,
    v.UserId,
    v.CreationDate,
    u.Reputation,
    u.DisplayName,
    p.Title,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  LEFT JOIN Users u ON u.Id = v.UserId
  WHERE v.VoteTypeId = 2 -- UpMod
),
ExpensiveWindow AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    ac.Id AS AnswerId,
    ac.CreationDate AS AnswerDate,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ac.CreationDate) AS rk
  FROM Posts p
  LEFT JOIN Posts ac ON ac.ParentId = p.Id
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
CrossJoinFilter AS (
  SELECT
    r.PostId,
    r.Reputation,
    r.DisplayName,
    r.Title AS PostTitle,
    r.Tags AS PostTags,
    r.CreationDate AS PostCreationDate,
    r.rn
  FROM RecentLikes r
  WHERE r.rn = 1
),
Final AS (
  SELECT
    c.PostId,
    c.PostTitle,
    c.PostCreationDate,
    c.PostTags,
    c.Reputation,
    c.DisplayName,
    t.TagName,
    s.TagCount,
    s.IsModeratorOnly,
    e.AnswerId,
    e.AnswerDate
  FROM CrossJoinFilter c
  LEFT JOIN Tags t ON POSITION('<' || t.TagName || '>' IN c.PostTags) > 0
  LEFT JOIN TagStats s ON s.TagName = t.TagName
  LEFT JOIN ExpensiveWindow e ON e.PostId = c.PostId AND e.rk = 1
)
SELECT
  PostId,
  PostTitle,
  PostCreationDate,
  PostTags,
  Reputation,
  DisplayName,
  TagName,
  TagCount,
  IsModeratorOnly,
  AnswerId,
  AnswerDate
FROM Final
ORDER BY PostCreationDate DESC, PostId DESC
LIMIT 100;