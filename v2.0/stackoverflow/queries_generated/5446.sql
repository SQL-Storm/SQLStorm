-- {"query": "5446.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1131} 
WITH
-- recent popular questions with complex scoring and tag filtering
PopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        (p.Score * 2 + p.ViewCount / NULLIF(p.CommentCount,0) + COALESCE(p.FavoriteCount,0) * 3)
        DESC,
        p.LastActivityDate DESC
    ) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate > CURRENT_DATE - INTERVAL '365 days'
),
-- correlate with user reputations and badges
UserBadges AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
-- compute a complex aggregated metric per question by joining with tags and votes
QuestionMetrics AS (
  SELECT
    pq.PostId,
    pq.Title,
    pq.CreationDate,
    pq.ViewCount,
    pq.Score,
    pq.OwnerUserId,
    pq.Tags,
    pq.AnswerCount,
    pq.CommentCount,
    pq.FavoriteCount,
    pq.LastActivityDate,
    ub.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    -- Derived metrics
    (pq.Score * 1.5) +
    (CASE WHEN pq.ViewCount > 1000 THEN 200 ELSE 0 END) +
    (CASE WHEN pq.AnswerCount > 5 THEN 150 ELSE 0 END) +
    (CASE WHEN pq.CommentCount > 20 THEN 100 ELSE 0 END) +
    (ub.Reputation / 100) +
    (ub.GoldBadges * 50) +
    (ub.SilverBadges * 20) +
    (ub.BronzeBadges * 10) AS CompositeScore
  FROM PopularQuestions pq
  JOIN UserBadges ub ON ub.UserId = pq.OwnerUserId
  WHERE pq.rn_by_owner = 1
),
-- correlated subquery: closest related posts via PostLinks (Linked/Duplicate)
RelatedPosts AS (
  SELECT
    qm.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    vt.Name AS LinkTypeName
  FROM QuestionMetrics qm
  LEFT JOIN PostLinks pl ON pl.PostId = qm.PostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Votes v ON v.PostId = qm.PostId
  LEFT JOIN PostTypes pt ON pt.Id = (SELECT PostTypeId FROM Posts WHERE Id = qm.PostId)
  LEFT JOIN LinkTypes vt ON vt.Id = pl.LinkTypeId
  WHERE pl.RelatedPostId IS NOT NULL
),
-- windowed view of comments and edits on the question for activity pattern
ActivityWindow AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.LastEditDate,
    p.CommentCount,
    p.ViewCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS rn_owner_activity
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate IS NOT NULL
)
SELECT
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.ViewCount,
  cm.Score,
  cm.OwnerUserId,
  cm.Tags,
  cm.AnswerCount,
  cm.CommentCount,
  cm.FavoriteCount,
  cm.LastActivityDate,
  cm.Reputation,
  cm.GoldBadges,
  cm.SilverBadges,
  cm.BronzeBadges,
  cm.CompositeScore,
  ARRAY_AGG(DISTINCT rt.RelatedPostId) FILTER (WHERE rt.RelatedPostId IS NOT NULL) AS RelatedPosts,
  MAX(a.LastActivityDate) KEEP (DENSE_RANK LAST ORDER BY a.LastActivityDate) AS LastRelatedActivity
FROM QuestionMetrics cm
LEFT JOIN RelatedPosts rt ON rt.PostId = cm.PostId
LEFT JOIN ActivityWindow a ON a.PostId = cm.PostId
GROUP BY
  cm.PostId, cm.Title, cm.CreationDate, cm.ViewCount, cm.Score, cm.OwnerUserId,
  cm.Tags, cm.AnswerCount, cm.CommentCount, cm.FavoriteCount, cm.LastActivityDate,
  cm.Reputation, cm.GoldBadges, cm.SilverBadges, cm.BronzeBadges, cm.CompositeScore
ORDER BY cm.CompositeScore DESC, cm.LastActivityDate DESC
LIMIT 50;