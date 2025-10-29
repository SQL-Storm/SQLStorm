-- {"query": "5159.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1163} 
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
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
active_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreateDate >= NOW() - INTERVAL '15 days'
),
correlated_summary AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate AS QuestionCreated,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.OwnerUserId,
    COUNT(DISTINCT rv.UserId) FILTER (WHERE rv.VoteTypeId = 2) AS UpVotesLast15d,
    COUNT(DISTINCT rv.UserId) FILTER (WHERE rv.VoteTypeId = 3) AS DownVotesLast15d,
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
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = bc.OwnerUserId AND p2.PostTypeId = 1) AS avg_owner_question_score
  FROM best_candidates bc
)
SELECT
  pc.PostId,
  pc.Title,
  pc.QuestionCreated,
  pc.QuestionScore,
  pc.ViewCount,
  pc.OwnerUserId,
  pc.UpVotesLast15d,
  pc.DownVotesLast15d,
  pc.TotalVotesLast15d,
  pc.TagUsage,
  cc.score_per_view,
  cc.net_votes_15d,
  cc.avg_owner_question_score,
  -- illustrative complex predicate with NULL handling and expressions
  CASE
    WHEN pc.TagUsage IS NULL THEN 'NoTags'
    ELSE CONCAT('TagCount=', pc.TagUsage)
  END AS tag_summary,
  CASE
    WHEN pc.ViewCount = 0 THEN NULL
    ELSE (pc.QuestionScore::double precision / pc.ViewCount)
  END AS score_per_view_adjusted,
  CASE
    WHEN pc.OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 1000) THEN true
    ELSE false
  END AS is_high_reputation_owner,
  ARRAY_AGG(DISTINCT lc.Name) FILTER (WHERE lc.Name IS NOT NULL) AS related_link_types
FROM complex_calcs cc
LEFT JOIN PostLinks pl ON pl.PostId = cc.PostId
LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
LEFT JOIN PostLinks pl2 ON pl2.PostId = cc.PostId
LEFT JOIN LinkTypes lc ON lc.Id = pl2.LinkTypeId
GROUP BY
  pc.PostId, pc.Title, pc.QuestionCreated, pc.QuestionScore, pc.ViewCount, pc.OwnerUserId,
  pc.UpVotesLast15d, pc.DownVotesLast15d, pc.TotalVotesLast15d, pc.TagUsage,
  cc.score_per_view, cc.net_votes_15d, cc.avg_owner_question_score
ORDER BY pc.QuestionCreated DESC
LIMIT 50;