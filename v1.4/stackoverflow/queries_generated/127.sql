-- {"query": "127.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2539} 
WITH
-- Base post set: questions with computed aggregates
QuestionPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Tags,
    (SELECT COALESCE(AVG(v.BountyAmount),0)
     FROM Votes v
     WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBounty,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS RealCommentCount,
    (SELECT p2.Score
     FROM Posts p2
     WHERE p2.Id = p.AcceptedAnswerId) AS AcceptedAnswerScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpModCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownModCount,
    (SELECT EXISTS (
        SELECT 1 FROM PostLinks pl
        WHERE pl.PostId = p.Id AND pl.RelatedPostId = p.Id
      )) AS HasSelfLinked,
    -- Tag array extraction from stored Tags string (e.g. "<c sharp><asp.net>")
    (SELECT ARRAY_AGG(t)
     FROM unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS t) AS TagArray
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
-- Historical close reason mapping via correlated subquery
CloseInfo AS (
  SELECT
    qp.Id,
    (SELECT HI.Comment
     FROM PostHistory hi
     WHERE hi.PostId = qp.Id AND hi.PostHistoryTypeId = 10
     ORDER BY hi.CreationDate DESC
     LIMIT 1) AS LastCloseReasonComment
  FROM QuestionPosts qp
),
-- Per-user badge influence (count of gold/silver/bronze badges)
UserBadges AS (
  SELECT
    q.OwnerUserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM QuestionPosts q
  LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
  GROUP BY q.OwnerUserId
),
-- Combined ranking with window functions
Ranked AS (
  SELECT
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.CommentCount,
    q.AcceptedAnswerScore,
    q.TagArray,
    cb.LastCloseReasonComment,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ROW_NUMBER() OVER (
      ORDER BY q.ViewCount DESC, q.Score DESC, ub.GoldBadges DESC, q.CreationDate ASC
    ) AS rn
  FROM QuestionPosts q
  LEFT JOIN CloseInfo cb ON cb.Id = q.Id
  LEFT JOIN UserBadges ub ON ub.OwnerUserId = q.OwnerUserId
  -- correlated subquery to bring in a related metric from the Votes table (upvotes minus downvotes)
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END),0) AS NetVotes
    FROM Votes v
    WHERE v.PostId = q.Id
  ) vx ON TRUE
)
SELECT
  r.Id,
  r.Title,
  r.OwnerName,
  r.CreationDate,
  r.ViewCount,
  r.Score,
  r.CommentCount,
  r.AcceptedAnswerScore,
  r.TagArray,
  r.LastCloseReasonComment,
  r.GoldBadges,
  r.SilverBadges,
  r.BronzeBadges,
  r.NetVotes
FROM Ranked r
LEFT JOIN LATERAL (
  SELECT
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 END),0) AS NetVotes
  FROM Votes v
  WHERE v.PostId = r.Id
) AS v ON TRUE
WHERE r.rn <= 100
UNION ALL
-- Secondary benchmark slice: recent answers with non-empty bodies and correlated tag checks
SELECT
  a.Id,
  a.Title,
  u.DisplayName AS OwnerName,
  a.CreationDate,
  a.ViewCount,
  a.Score,
  a.CommentCount,
  NULL AS AcceptedAnswerScore,
  (SELECT ARRAY_AGG(t) FROM unnest(string_to_array(substr(a.Tags, 2, length(a.Tags)-2), '><')) AS t) AS TagArray,
  NULL AS LastCloseReasonComment,
  NULL AS GoldBadges,
  NULL AS SilverBadges,
  NULL AS BronzeBadges,
  NULL AS NetVotes
FROM Posts a
LEFT JOIN Users u ON a.OwnerUserId = u.Id
WHERE a.PostTypeId = 2
  AND a.Body IS NOT NULL
  AND a.Body <> ''
ORDER BY OwnerName NULLS FIRST, CreationDate DESC
LIMIT 50;