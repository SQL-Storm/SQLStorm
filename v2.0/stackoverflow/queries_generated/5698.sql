-- {"query": "5698.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 859} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.CommunityOwnedDate,
    p.ContentLicense,
    json_agg(
      json_build_object(
        'VoteTypeId', v.VoteTypeId,
        'UserId', v.UserId,
        'CreationDate', v.CreationDate,
        'BountyAmount', v.BountyAmount
      )
      ORDER BY v.CreationDate
    ) FILTER (WHERE v.VoteTypeId IS NOT NULL) AS VotesTimeline
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = p.Id
  WHERE p.PostTypeId IN (1,2)
  GROUP BY
    p.Id, p.PostTypeId, p.Title, p.CreationDate, p.LastActivityDate,
    p.Score, p.ViewCount, p.OwnerUserId, p.Tags, p.AnswerCount, p.CommentCount,
    p.FavoriteCount, p.Body, p.ParentId, p.AcceptedAnswerId, p.LastEditorUserId,
    p.LastEditDate, p.CommunityOwnedDate, p.ContentLicense
),
deadlock_probe AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.CommunityOwnedDate,
    rp.ContentLicense,
    rp.VotesTimeline,
    -- compute a complex derived metric with NULL-safe logic
    (CASE WHEN rp.Score IS NULL THEN 0 ELSE rp.Score END
     + COALESCE((SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = rp.PostId AND v2.BountyAmount IS NOT NULL), 0)
     + (SELECT SUM(CASE WHEN v3.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v3 WHERE v3.PostId = rp.PostId)
    ) AS performance_metric
  FROM ranked_posts rp
),
windowed AS (
  SELECT
    d.*,
    ROW_NUMBER() OVER (
      PARTITION BY d.OwnerUserId
      ORDER BY d.LastActivityDate DESC, d.CreationDate ASC
    ) AS rn_owner,
    RANK() OVER (
      ORDER BY d.performance_metric DESC
    ) AS rnk_perf
  FROM deadlock_probe d
)
SELECT
  w.PostId,
  w.Title,
  w.CreationDate,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.OwnerUserId,
  w.Tags,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.Body,
  w.ParentId,
  w.AcceptedAnswerId,
  w.LastEditorUserId,
  w.LastEditDate,
  w.CommunityOwnedDate,
  w.ContentLicense,
  w.VotesTimeline,
  w.performance_metric,
  w.rn_owner,
  w.rnk_perf
FROM windowed w
WHERE
  w.rn_owner <= 5 -- top 5 by activity per user
  AND w.rnk_perf <= 20 -- top 20 by derived performance metric across all posts
ORDER BY w.rnk_perf, w.LastActivityDate DESC
OPTION (MAXDOP 4);