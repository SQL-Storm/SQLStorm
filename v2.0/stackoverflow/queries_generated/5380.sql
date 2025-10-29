-- {"query": "5380.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1195} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.ProfileImageUrl,
    CASE
      WHEN p.OwnerUserId IS NULL THEN NULL
      ELSE (SELECT COUNT(*) FROM Posts AS a WHERE a.OwnerUserId = p.OwnerUserId AND a.PostTypeId = 1 AND a.CreationDate >= p.CreationDate - INTERVAL '30 days') 
    END AS RecentQuestionCountByOwner,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.ViewCount DESC,
        p.Score DESC,
        p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
Agg AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.PostTypeId,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.ViewCount,
    rp.Score,
    rp.Tags,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.Body,
    rp.ContentLicense,
    rp.Reputation,
    rp.DisplayName,
    rp.LastAccessDate,
    rp.Views,
    rp.UpVotes,
    rp.DownVotes,
    rp.Location,
    rp.ProfileImageUrl,
    rp.RecentQuestionCountByOwner,
    rp.rn_by_type,
    -- Add a correlated subquery: total upvotes for the owner's questions in the last 60 days
    (
      SELECT COALESCE(SUM(v.BountyAmount), 0)
      FROM Votes v
      JOIN Posts q ON v.PostId = q.Id
      WHERE q.OwnerUserId = rp.OwnerUserId
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '60 days'
        AND v.VoteTypeId = 2
    ) AS OwnerRecentUpvoteSum60d,
    -- Windowed metric: rank of the post among all posts by score within last 90 days
    DENSE_RANK() OVER (
      PARTITION BY rp.PostTypeId
      ORDER BY rp.Score DESC, rp.LastActivityDate DESC
    ) AS TypeScoreRank90d
  FROM RankedPosts rp
  LEFT JOIN LATERAL (
    SELECT 1
  ) AS l ON TRUE
  WHERE rp.rn_by_type <= 100
),
SetOp AS (
  -- union of high-traffic questions with recent activity and low-traffic answers
  SELECT
    a.Id, a.Title, a.PostTypeId, a.CreationDate, a.OwnerUserId, a.ViewCount, a.Score,
    a.Tags, a.LastActivityDate, a.CommentCount, a.AnswerCount, a.FavoriteCount, a.Body,
    a.ContentLicense, a.Reputation, a.DisplayName, a.LastAccessDate, a.Views, a.UpVotes,
    a.DownVotes, a.Location, a.ProfileImageUrl, a.RecentQuestionCountByOwner,
    a.rn_by_type, a.OwnerRecentUpvoteSum60d, a.TypeScoreRank90d
  FROM Agg a
  WHERE a.PostTypeId = 1
    AND a.ViewCount > 1000
  UNION ALL
  SELECT
    b.Id, b.Title, b.PostTypeId, b.CreationDate, b.OwnerUserId, b.ViewCount, b.Score,
    b.Tags, b.LastActivityDate, b.CommentCount, b.AnswerCount, b.FavoriteCount, b.Body,
    b.ContentLicense, b.Reputation, b.DisplayName, b.LastAccessDate, b.Views, b.UpVotes,
    b.DownVotes, b.Location, b.ProfileImageUrl, b.RecentQuestionCountByOwner,
    b.rn_by_type, b.OwnerRecentUpvoteSum60d, b.TypeScoreRank90d
  FROM Agg b
  WHERE b.PostTypeId = 2
    AND b.Score < 0
)
SELECT
  s.Id,
  s.Title,
  s.PostTypeId,
  s.CreationDate,
  s.OwnerUserId,
  s.ViewCount,
  s.Score,
  s.Tags,
  s.LastActivityDate,
  s.CommentCount,
  s.AnswerCount,
  s.FavoriteCount,
  s.Body,
  s.ContentLicense,
  s.Reputation,
  s.DisplayName,
  s.LastAccessDate,
  s.Views,
  s.UpVotes,
  s.DownVotes,
  s.Location,
  s.ProfileImageUrl,
  s.RecentQuestionCountByOwner,
  s.rn_by_type,
  s.OwnerRecentUpvoteSum60d,
  s.TypeScoreRank90d
FROM SetOp s
LEFT JOIN PostLinks pl ON pl.PostId = s.Id
LEFT JOIN PostLinks pl2 ON pl2.PostId = s.Id
LEFT JOIN Tags t ON t.WikiPostId = s.Id OR t.ExcerptPostId = s.Id
WHERE s.rn_by_type = 1
  AND (pl.LinkTypeId = 1 OR pl2.LinkTypeId = 3)
ORDER BY s.TypeScoreRank90d, s.LastActivityDate DESC
LIMIT 200;