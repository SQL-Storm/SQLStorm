-- {"query": "5783.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 766} 
WITH flagged_by_user AS (
  SELECT
    v.PostId,
    v.UserId AS VoterUserId,
    u.DisplayName AS VoterName,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    p.OwnerUserId AS PostOwnerId,
    o.DisplayName AS OwnerName,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate AS PostCreationDate
  FROM Votes v
  INNER JOIN Posts p ON v.PostId = p.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  LEFT JOIN Users o ON p.OwnerUserId = o.Id
  WHERE v.VoteTypeId = 2 -- UpMod
    AND p.PostTypeId = 1 -- Questions
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
complex_calc AS (
  SELECT
    f.PostId,
    f.VoterUserId,
    f.VoterName,
    f.VoteTypeId,
    f.VoteDate,
    f.PostOwnerId,
    f.OwnerName,
    f.Title,
    f.Tags,
    f.Score,
    f.ViewCount,
    f.PostCreationDate,
    COALESCE(NULLIF(p.Title, ''), 'Untitled') AS CleanTitle,
    g.rn
  FROM flagged_by_user f
  INNER JOIN recent_activity g ON f.PostId = g.PostId
  LEFT JOIN top_tags tt ON f.Title LIKE '%' || tt.TagName || '%'
  WHERE g.rn = 1
),
windowed AS (
  SELECT
    PostId,
    VoterUserId,
    VoterName,
    VoteTypeId,
    VoteDate,
    PostOwnerId,
    OwnerName,
    Title,
    Tags,
    Score,
    ViewCount,
    PostCreationDate,
    CleanTitle,
    rn,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY PostOwnerId) AS UpvotesByOwner,
    AVG(Score) OVER (PARTITION BY PostOwnerId) AS AvgScoreByOwner
  FROM complex_calc
)
SELECT
  w.PostId,
  w.Title AS QuestionTitle,
  w.Tags,
  w.Score,
  w.ViewCount,
  w.PostCreationDate,
  w.OwnerName AS OwnerDisplayName,
  w.UpvotesByOwner,
  w.AvgScoreByOwner,
  ARRAY_AGG(DISTINCT jsonb_build_object(
    'voter', w.VoterName,
    'voteType', w.VoteTypeId,
    'voteDate', w.VoteDate
  )) OVER (PARTITION BY w.PostId) AS VoteHistory,
  CASE
    WHEN w.Tags LIKE '%[Performance]%' THEN 'Perf'
    WHEN w.Tags LIKE '%[SQL]%' THEN 'SQL'
    ELSE 'General'
  END AS BenchmarkTag
FROM windowed w
ORDER BY w.PostCreationDate DESC
LIMIT 100;