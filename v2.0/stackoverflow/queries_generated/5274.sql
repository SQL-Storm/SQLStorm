-- {"query": "5274.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 815} 
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
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
top_in_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS question_count,
    AVG(p.Score) AS avg_score,
    AVG(p.ViewCount) AS avg_views
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
           p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.CreationDate >= NOW() - INTERVAL '60 days'
  ) s
  JOIN Posts p ON p.Id = s.PostId
  JOIN Tags t ON LOWER(t.TagName) = LOWER(s.TagName)
  GROUP BY t.TagName
),
activity_by_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCreated
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
complex_series AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.UpVotes,
    rp.DownVotes,
    COALESCE(pv.BountyAmount, 0) AS BountyAmount,
    CASE
      WHEN rp.Score > 10 AND rp.ViewCount > 1000 THEN true
      ELSE false
    END AS HotFlag
  FROM recent_questions rp
  LEFT JOIN (
    SELECT PostId, MAX(BountyAmount) AS BountyAmount
    FROM Votes
    WHERE VoteTypeId = 8 -- BountyStart
    GROUP BY PostId
  ) pv ON pv.PostId = rp.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.UpVotes,
  c.DownVotes,
  c.BountyAmount,
  c.HotFlag,
  a.DisplayName AS OwnerDisplayName,
  a.Reputation,
  t.TagName
FROM complex_series c
LEFT JOIN Users a ON a.Id = (SELECT OwnerUserId FROM Posts p WHERE p.Id = c.PostId)
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substring(c.Tags, 2, length(c.Tags)-2), '><')) AS TagName
) t ON true
ORDER BY c.LastActivityDate DESC
LIMIT 100;