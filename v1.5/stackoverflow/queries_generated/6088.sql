-- {"query": "6088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 955} 
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.Location,
    u.ProfileImageUrl,
    LISTAGG(bt.Name, ',') WITHIN GROUP (ORDER BY bt.Date) AS BadgesEarned
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Badges bt ON bt.UserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount,
    p.OwnerUserId, p.LastActivityDate, p.AnswerCount, p.CommentCount,
    p.FavoriteCount, p.Body, p.ContentLicense, u.DisplayName, u.Reputation,
    u.LastAccessDate, u.Location, u.ProfileImageUrl
),
recent_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerDisplayName,
    q.Reputation,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.BadgesEarned,
    ROW_NUMBER() OVER (
      PARTITION BY q.OwnerDisplayName
      ORDER BY q.LastActivityDate DESC, q.Score DESC, q.ViewCount DESC
    ) AS rn
  FROM top_questions q
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
  LEFT JOIN Votes v ON v.PostId = q.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = q.PostId
  WHERE (q.Reputation > 1000 OR q.ViewCount > 1000)
),
complex_metrics AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerDisplayName,
    ra.LastActivityDate,
    ra.ViewCount,
    ra.Score,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.BadgesEarned,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvotes,
    MAX(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasDownvotes,
    COUNT(DISTINCT cl.Id) FILTER (WHERE c.Id IS NULL) AS OrphanedComments,
    MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedAt,
    SUM(CASE WHEN t.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedVotes
  FROM recent_activity ra
  LEFT JOIN Votes v ON v.PostId = ra.PostId
  LEFT JOIN Comments c ON c.PostId = ra.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = ra.PostId
  LEFT JOIN PostHistoryTypes t ON ph.PostHistoryTypeId = t.Id
  LEFT JOIN PostLinks pl ON pl.PostId = ra.PostId
  LEFT JOIN PostLinks cl ON cl.RelatedPostId = ra.PostId
  GROUP BY
    ra.PostId, ra.Title, ra.OwnerDisplayName, ra.LastActivityDate,
    ra.ViewCount, ra.Score, ra.AnswerCount, ra.CommentCount, ra.FavoriteCount,
    ra.BadgesEarned
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.LastActivityDate,
  cm.ViewCount,
  cm.Score,
  cm.AnswerCount,
  cm.CommentCount,
  cm.FavoriteCount,
  cm.BadgesEarned,
  cm.HasUpvotes,
  cm.HasDownvotes,
  cm.OrphanedComments,
  cm.ClosedAt,
  cm.AcceptedVotes
FROM complex_metrics cm
LEFT JOIN LATERAL (
  SELECT
    1 AS dummy
  WHERE cm.LastActivityDate > NOW() - INTERVAL '30 days'
) AS recent ON TRUE
WHERE cm.LastActivityDate IS NOT NULL
ORDER BY cm.LastActivityDate DESC, cm.Score DESC
FETCH FIRST 100 ROWS ONLY;