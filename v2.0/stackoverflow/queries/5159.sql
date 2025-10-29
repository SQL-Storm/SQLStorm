WITH
recent_questions AS (
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
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
active_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = false
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '15 days'
),
correlated_summary AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate AS QuestionCreated,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.OwnerUserId,
    COUNT(DISTINCT CASE WHEN rv.VoteTypeId = 2 THEN rv.UserId END) AS UpVotesLast15d,
    COUNT(DISTINCT CASE WHEN rv.VoteTypeId = 3 THEN rv.UserId END) AS DownVotesLast15d,
    COUNT(DISTINCT rv.PostId) AS TotalVotesLast15d,
    ab.Count AS TagUsage
  FROM recent_questions rq
  LEFT JOIN recent_votes rv ON rv.PostId = rq.PostId
  LEFT JOIN (
    SELECT t.ExcerptPostId, t.Count
    FROM Tags t
  ) ab ON ab.ExcerptPostId = rq.PostId
  GROUP BY rq.PostId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId, ab.Count
),
windowed AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.QuestionCreated,
    cs.QuestionScore,
    cs.ViewCount,
    cs.OwnerUserId,
    cs.UpVotesLast15d,
    cs.DownVotesLast15d,
    cs.TotalVotesLast15d,
    cs.TagUsage,
    ROW_NUMBER() OVER (
      PARTITION BY cs.OwnerUserId
      ORDER BY cs.QuestionScore DESC, cs.TotalVotesLast15d DESC, cs.UpVotesLast15d DESC
    ) AS rn_by_owner
  FROM correlated_summary cs
),
best_candidates AS (
  SELECT
    w.PostId,
    w.Title,
    w.QuestionCreated,
    w.QuestionScore,
    w.ViewCount,
    w.OwnerUserId,
    w.UpVotesLast15d,
    w.DownVotesLast15d,
    w.TotalVotesLast15d,
    w.TagUsage
  FROM windowed w
  WHERE w.rn_by_owner <= 5
),
complex_calcs AS (
  SELECT
    bc.PostId,
    bc.Title,
    bc.QuestionCreated,
    bc.QuestionScore,
    bc.ViewCount,
    bc.OwnerUserId,
    bc.UpVotesLast15d,
    bc.DownVotesLast15d,
    bc.TotalVotesLast15d,
    bc.TagUsage,
    (bc.QuestionScore * 1.0) / NULLIF(bc.ViewCount, 0) AS score_per_view,
    (bc.UpVotesLast15d - bc.DownVotesLast15d) AS net_votes_15d,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = bc.OwnerUserId AND p2.PostTypeId = 1) AS avg_owner_question_score
  FROM best_candidates bc
)
SELECT
  cc.PostId,
  cc.Title,
  cc.QuestionCreated,
  cc.QuestionScore,
  cc.ViewCount,
  cc.OwnerUserId,
  cc.UpVotesLast15d,
  cc.DownVotesLast15d,
  cc.TotalVotesLast15d,
  cc.TagUsage,
  cc.score_per_view,
  cc.net_votes_15d,
  cc.avg_owner_question_score,
  CASE
    WHEN cc.TagUsage IS NULL THEN 'NoTags'
    ELSE 'TagCount=' || CAST(cc.TagUsage AS text)
  END AS tag_summary,
  CASE
    WHEN cc.ViewCount = 0 THEN NULL
    ELSE (CAST(cc.QuestionScore AS double precision) / cc.ViewCount)
  END AS score_per_view_adjusted,
  CASE
    WHEN cc.OwnerUserId IN (SELECT u.Id FROM Users u WHERE u.Reputation > 1000) THEN true
    ELSE false
  END AS is_high_reputation_owner,
  ARRAY_AGG(DISTINCT lc.Name) FILTER (WHERE lc.Name IS NOT NULL) AS related_link_types
FROM complex_calcs cc
LEFT JOIN PostLinks pl ON pl.PostId = cc.PostId
LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
LEFT JOIN PostLinks pl2 ON pl2.PostId = cc.PostId
LEFT JOIN LinkTypes lc ON lc.Id = pl2.LinkTypeId
GROUP BY
  cc.PostId, cc.Title, cc.QuestionCreated, cc.QuestionScore, cc.ViewCount, cc.OwnerUserId,
  cc.UpVotesLast15d, cc.DownVotesLast15d, cc.TotalVotesLast15d, cc.TagUsage,
  cc.score_per_view, cc.net_votes_15d, cc.avg_owner_question_score
ORDER BY cc.QuestionCreated DESC
LIMIT 50;