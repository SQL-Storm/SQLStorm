WITH
post_votes AS (
  SELECT p.Id AS PostId, p.PostTypeId, p.OwnerUserId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
    COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorites,
    SUM(CASE WHEN v.VoteTypeId IN (1,2) THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS vote_balance,
    MAX(v.CreationDate) AS last_vote_date
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.PostTypeId, p.OwnerUserId
),
tag_list AS (
  SELECT p.Id AS PostId, trim(t) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, greatest(length(coalesce(p.Tags, '')) - 2,0)), '><')) AS t
  ) tags
  WHERE p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_rank AS (
  SELECT Tag, COUNT(*) AS tag_count,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS rnk
  FROM tag_list
  GROUP BY Tag
),
user_badges AS (
  SELECT b.UserId, COUNT(*) AS badges_total,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
    SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = TRUE THEN 1 ELSE 0 END) AS tag_based,
    MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
answer_metrics AS (
  SELECT a.ParentId AS QuestionId,
    COUNT(CASE WHEN a.Score >= 0 THEN 1 END) AS nonneg_answers,
    COUNT(CASE WHEN a.Score < 0 THEN 1 END) AS neg_answers,
    AVG(a.Score) AS avg_answer_score,
    MAX(a.Score) AS max_answer_score,
    MIN(a.Score) AS min_answer_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY a.Score) AS median_answer_score
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
link_counts AS (
  SELECT pl.PostId, lt.Name AS LinkType, COUNT(*) AS cnt
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId, lt.Name
),
recent_activity AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score,
    pv.upvotes, pv.downvotes, pv.vote_balance,
    COALESCE(am.avg_answer_score, 0) AS q_avg_ans_score,
    COALESCE(am.median_answer_score, 0) AS q_median_ans_score,
    COALESCE(ub.badges_total, 0) AS owner_badges,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC NULLS LAST, p.Score DESC NULLS LAST) AS owner_post_rank,
    DENSE_RANK() OVER (ORDER BY COALESCE(p.Score,0) DESC) AS global_score_rank
  FROM Posts p
  LEFT JOIN post_votes pv ON pv.PostId = p.Id
  LEFT JOIN answer_metrics am ON am.QuestionId = p.Id
  LEFT JOIN user_badges ub ON ub.UserId = p.OwnerUserId
),
top_commenter_per_post AS (
  SELECT c.PostId, c.UserId, SUM(COALESCE(c.Score,0)) AS total_comment_score,
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY SUM(COALESCE(c.Score,0)) DESC NULLS LAST) AS rn
  FROM Comments c
  WHERE c.UserId IS NOT NULL
  GROUP BY c.PostId, c.UserId
),
comments_agg AS (
  SELECT PostId, UserId AS top_commenter_userid, total_comment_score
  FROM top_commenter_per_post WHERE rn = 1
),
questions_with_tags AS (
  SELECT q.Id AS QuestionId, q.Title, q.CreationDate, q.Score AS QuestionScore, q.ViewCount,
    q.OwnerUserId,
    COALESCE(tt.tag_count, 0) AS tag_popularity,
    COALESCE(pv.upvotes, 0) AS q_upvotes, COALESCE(pv.downvotes, 0) AS q_downvotes,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS has_accepted,
    COALESCE(am.nonneg_answers + am.neg_answers, 0) AS answer_count,
    COALESCE(MAX(CASE WHEN la.Name = 'Duplicate' THEN la.cnt END), 0) AS duplicate_links,
    COALESCE(MAX(CASE WHEN la.Name = 'Linked' THEN la.cnt END), 0) AS linked_posts
  FROM Posts q
  LEFT JOIN post_votes pv ON pv.PostId = q.Id
  LEFT JOIN answer_metrics am ON am.QuestionId = q.Id
  LEFT JOIN (
    SELECT pl.PostId, lt.Name, COUNT(*) AS cnt
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId, lt.Name
  ) la ON la.PostId = q.Id
  LEFT JOIN (
    SELECT tl.PostId, MAX(tr.tag_count) AS tag_count
    FROM tag_list tl
    JOIN tag_rank tr ON tr.Tag = tl.Tag AND tr.rnk <= 100
    GROUP BY tl.PostId
  ) tt ON tt.PostId = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId,
    tt.tag_count, pv.upvotes, pv.downvotes, q.AcceptedAnswerId, am.nonneg_answers, am.neg_answers
),
expensive_calc AS (
  SELECT r.*,
    (
      COALESCE(r.QuestionScore, 0) * (CASE WHEN r.answer_count = 0 THEN 1 ELSE r.answer_count END) * 1.0 / NULLIF(GREATEST(r.ViewCount,0),0)
      + COALESCE(r.q_median_ans_score, 0)
      - (SELECT COALESCE(MAX(V.BountyAmount),0) FROM Votes V WHERE V.PostId = r.QuestionId AND V.BountyAmount IS NOT NULL)
    ) AS hotness_score,
    left(replace(coalesce(r.Title, ''), '&lt;', '<'), 120) || ' [' || coalesce(NULLIF(trim(u.DisplayName), ''), 'community') || ']' AS short_title,
    CASE
      WHEN r.q_upvotes >= 100 AND r.q_median_ans_score < 0 THEN 'controversial'
      WHEN r.q_upvotes >= 50 AND r.answer_count = 0 THEN 'popular-unanswered'
      WHEN r.has_accepted = 1 AND r.q_upvotes > 0 THEN 'solved'
      ELSE NULL
    END AS tag_label
  FROM (
    SELECT qwt.QuestionId, qwt.Title, qwt.CreationDate, qwt.QuestionScore, qwt.ViewCount, qwt.tag_popularity,
      qwt.q_upvotes, qwt.q_downvotes, qwt.has_accepted, qwt.answer_count, qwt.OwnerUserId,
      COALESCE(am.median_answer_score, 0) AS q_median_ans_score
    FROM questions_with_tags qwt
    LEFT JOIN answer_metrics am ON am.QuestionId = qwt.QuestionId
  ) r
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
)
SELECT e.QuestionId,
  e.short_title,
  e.CreationDate,
  e.hotness_score,
  e.tag_popularity,
  e.q_upvotes,
  e.q_downvotes,
  e.answer_count,
  e.tag_label,
  COALESCE(cb.top_commenter_userid, -1) AS top_commenter_userid,
  COALESCE(ub.gold, 0) AS owner_gold_badges,
  CASE WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.AcceptedAnswerId = e.QuestionId) THEN TRUE ELSE FALSE END AS has_accepted_as_answer_elsewhere,
  (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = e.QuestionId AND a.PostTypeId = 2) AS first_answer_date,
  EXTRACT(EPOCH FROM COALESCE((SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = e.QuestionId AND a.PostTypeId = 2), e.CreationDate) - e.CreationDate)/86400.0 AS days_to_first_answer,
  (
    SELECT string_agg(s.Tag, ', ')
    FROM (
      SELECT t.Tag
      FROM (
        SELECT unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, greatest(length(coalesce(p.Tags, '')) - 2,0)), '><')) AS Tag
        FROM Posts p WHERE p.Id = e.QuestionId
      ) t
      JOIN tag_rank tr ON tr.Tag = t.Tag
      ORDER BY tr.tag_count DESC
      LIMIT 3
    ) s
  ) AS top_tags_preview
FROM expensive_calc e
LEFT JOIN comments_agg cb ON cb.PostId = e.QuestionId
LEFT JOIN Users u2 ON u2.Id = e.OwnerUserId
LEFT JOIN user_badges ub ON ub.UserId = u2.Id
WHERE (e.hotness_score IS NOT NULL AND (e.hotness_score > 10 OR (e.q_upvotes >= 20 AND e.answer_count >= 2)))
  AND (e.tag_popularity IS NULL OR e.tag_popularity > 0 OR e.tag_label IS NOT NULL)
ORDER BY e.hotness_score DESC NULLS LAST, e.CreationDate ASC
LIMIT 250;