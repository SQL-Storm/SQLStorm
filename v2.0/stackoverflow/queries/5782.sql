-- {"query": "5782.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1188}
WITH recent_q AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.ViewCount,
         p.Score,
         p.Tags,
         p.OwnerUserId,
         p.LastActivityDate,
         p.AcceptedAnswerId,
         p.CommentCount,
         p.FavoriteCount,
         p.PostTypeId,
         p.Body,
         p.ParentId,
         p.LastEditDate,
         p.LastEditorUserId,
         p.LastEditorDisplayName
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
votes_by_post AS (
  SELECT PostId, COUNT(*) AS upvote_count
  FROM Votes
  WHERE VoteTypeId = 2
  GROUP BY PostId
),
badges_by_user AS (
  SELECT UserId, COUNT(*) AS gold
  FROM Badges
  WHERE Class = 1
  GROUP BY UserId
),
closed_by_post AS (
  SELECT PostId, COUNT(*) AS cnt
  FROM PostHistory
  WHERE PostHistoryTypeId = 10
  GROUP BY PostId
),
q_with_metrics AS (
  SELECT 
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.Tags,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.AcceptedAnswerId,
    rq.CommentCount,
    rq.FavoriteCount,
    rq.PostTypeId,
    rq.Body,
    rq.ParentId,
    rq.LastEditDate,
    rq.LastEditorUserId,
    rq.LastEditorDisplayName,
    COALESCE(vs.upvote_count, 0) AS UpVotesFromVotes,
    COALESCE(bd.gold, 0) AS GoldBadges,
    COALESCE(closed.cnt, 0) AS CloseVotes
  FROM recent_q rq
  LEFT JOIN votes_by_post vs ON vs.PostId = rq.PostId
  LEFT JOIN badges_by_user bd ON bd.UserId = rq.OwnerUserId
  LEFT JOIN closed_by_post closed ON closed.PostId = rq.PostId
),
complex_flags AS (
  SELECT
    qwu.PostId,
    qwu.Title,
    qwu.CreationDate,
    qwu.ViewCount,
    qwu.Score,
    qwu.Tags,
    qwu.OwnerUserId,
    qwu.LastActivityDate,
    qwu.AcceptedAnswerId,
    qwu.CommentCount,
    qwu.FavoriteCount,
    qwu.PostTypeId,
    qwu.Body,
    qwu.ParentId,
    qwu.LastEditDate,
    qwu.LastEditorUserId,
    qwu.LastEditorDisplayName,
    qwu.UpVotesFromVotes,
    qwu.GoldBadges,
    qwu.CloseVotes,
    ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('day', qwu.CreationDate)
                       ORDER BY qwu.Score DESC, qwu.ViewCount DESC) AS rn_per_day,
    AVG(qwu.Score) OVER (PARTITION BY DATE_TRUNC('week', qwu.CreationDate)) AS avg_score_per_week
  FROM q_with_metrics qwu
),
outer_join_demo AS (
  SELECT
    c1.PostId,
    c1.Title,
    c1.CreationDate,
    c1.ViewCount,
    c1.Score,
    c1.Tags,
    c1.OwnerUserId,
    c1.LastActivityDate,
    c1.AcceptedAnswerId,
    c1.CommentCount,
    c1.FavoriteCount,
    c1.PostTypeId,
    c1.Body,
    c1.ParentId,
    c1.LastEditDate,
    c1.LastEditorUserId,
    c1.LastEditorDisplayName,
    c1.UpVotesFromVotes,
    c1.GoldBadges,
    c1.CloseVotes,
    c1.rn_per_day,
    c1.avg_score_per_week,
    (
      SELECT COUNT(*) 
      FROM Comments co
      WHERE co.PostId = c1.PostId
        AND co.UserDisplayName IS NOT NULL
    ) AS CommentersCount
  FROM complex_flags c1
  WHERE c1.rn_per_day = 1
),
links_by_post AS (
  SELECT PostId, COUNT(*) AS LinkedCount
  FROM PostLinks
  WHERE LinkTypeId = 1 OR LinkTypeId = 3
  GROUP BY PostId
)
SELECT
  od.PostId,
  od.Title,
  od.CreationDate,
  od.ViewCount,
  od.Score,
  od.OwnerUserId,
  od.LastActivityDate,
  od.AcceptedAnswerId,
  od.CommentCount,
  od.FavoriteCount,
  od.PostTypeId,
  od.Body,
  od.ParentId,
  od.LastEditDate,
  od.LastEditorUserId,
  od.LastEditorDisplayName,
  od.UpVotesFromVotes,
  od.GoldBadges,
  od.CloseVotes,
  od.rn_per_day,
  od.avg_score_per_week,
  od.CommentersCount,
  COALESCE(lk.LinkedCount, 0) AS RelatedLinks
FROM outer_join_demo od
LEFT JOIN links_by_post lk ON lk.PostId = od.PostId
WHERE od.PostTypeId = 1
  AND od.ViewCount > 0
ORDER BY od.Score DESC, od.ViewCount DESC
OFFSET 0 LIMIT 100;