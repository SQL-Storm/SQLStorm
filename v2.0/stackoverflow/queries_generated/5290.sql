-- {"query": "5290.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 936} 
WITH flagged_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    c.Id AS CommentId,
    c.Text AS CommentText,
    v.CreationDate AS VoteDate,
    v.VoteTypeId,
    v.UserId AS VoterId,
    u.DisplayName AS VoterName,
    ro.Class AS CloseClass,
    ro.Name AS CloseReason
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  LEFT JOIN PostHistory h ON h.PostId = p.Id
  LEFT JOIN PostHistoryTypes htypes ON htypes.Id = h.PostHistoryTypeId
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
  LEFT JOIN CloseReasonTypes ro ON CAST(h.Comment AS varchar) LIKE '%' || ro.Id::varchar || '%'
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
),
latest_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
complex_query AS (
  SELECT
    lb.PostId,
    lb.Title,
    lb.OwnerUserId,
    lb.LastActivityDate,
    lb.Score,
    lb.ViewCount,
    lb.Tags,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = lb.OwnerUserId AND p2.PostTypeId = 1) AS PostCountByOwner,
    (SELECT AVG(Score) FROM Posts p3 WHERE p3.OwnerUserId = lb.OwnerUserId) AS AvgOwnerScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = lb.PostId AND v.VoteTypeId = 2) AS UpVotesOnPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = lb.PostId AND v.VoteTypeId = 3) AS DownVotesOnPost,
    (SELECT MAX(CASE WHEN v2.VoteTypeId = 2 THEN v2.CreationDate END) FROM Votes v2 WHERE v2.PostId = lb.PostId) AS LastUpVoteDate
  FROM latest_activity lb
  WHERE lb.rn = 1
)
SELECT
  lc.PostId,
  lc.Title,
  lc.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  lc.LastActivityDate,
  lc.Score,
  lc.ViewCount,
  lc.Tags,
  lc.PostCountByOwner,
  lc.AvgOwnerScore,
  lc.UpVotesOnPost,
  lc.DownVotesOnPost,
  lc.LastUpVoteDate,
  CASE
    WHEN u.Reputation < 1000 THEN 'Low'
    WHEN u.Reputation < 10000 THEN 'Medium'
    ELSE 'High'
  END AS OwnerTier,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = lc.OwnerUserId) AS BadgeCount,
  (SELECT ARRAY_AGG(bt.Name) FROM Badges b2 JOIN Badges bb ON bb.UserId = b2.UserId WHERE b2.UserId = lc.OwnerUserId) AS BadgeNames
FROM complex_query lc
JOIN Users u ON u.Id = lc.OwnerUserId
LEFT JOIN Tags t ON t.Id = (SELECT CAST(SPLIT_PART(lc.Tags, '<>', 1) AS int))
ORDER BY lc.LastActivityDate DESC
LIMIT 100;