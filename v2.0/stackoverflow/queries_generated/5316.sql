-- {"query": "5316.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 827} 
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
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
),
q_with_owner AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rq.ContentLicense,
    rq.rn,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 3) AS DownVotes
  FROM recent_questions rq
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
  WHERE rq.rn <= 5
),
trend AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    -- window: moving average of views over last 7 days (simulated via date arithmetic)
    AVG(CASE WHEN DATEDIFF(day, p.CreationDate, GETDATE()) <= 7 THEN p.ViewCount END) OVER () AS AvgViewsLast7,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotesForPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
),
complex AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tags,
    t.CreationDate,
    t.LastActivityDate,
    t.ViewCount,
    t.Score,
    t.CommentCount,
    t.AnswerCount,
    t.FavoriteCount,
    t.ContentLicense,
    (CASE
       WHEN t.ViewCount > 1000 THEN 'Hot'
       WHEN t.ViewCount BETWEEN 100 AND 1000 THEN 'Warm'
       ELSE 'Cold'
     END) AS ViewBucket,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = t.PostId) AS CommentCountAll,
    (SELECT STRING_AGG(CAST(v2.VoteTypeId AS varchar), ',') FROM Votes v2 WHERE v2.PostId = t.PostId) AS AllVoteTypes
  FROM trend t
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.ContentLicense,
  c.ViewBucket,
  c.CommentCountAll,
  c.AllVoteTypes,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.CreationDate AS OwnerCreationDate,
  u.LastAccessDate AS OwnerLastAccessDate
FROM complex c
LEFT JOIN Users u ON (
  -- correlated subquery: pick owner as the user with the highest reputation among owners in this batch
  u.Id = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = c.PostId)
)
ORDER BY c.LastActivityDate DESC
LIMIT 20;