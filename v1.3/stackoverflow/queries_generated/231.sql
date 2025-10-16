-- {"query": "231.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3793} 
WITH
question_base AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
),
tag_expansion AS (
  SELECT q.Id AS QuestionId,
         trim(both ' ' FROM t.tag) AS Tag
  FROM question_base q
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, char_length(q.Tags) - 2), '><')) AS t(tag)
),
answers AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 2
),
answer_agg AS (
  SELECT a.ParentId                               AS QuestionId,
         COUNT(*)                                AS AnswerCount,
         AVG(a.Score)                            AS AvgAnswerScore,
         MAX(a.Score)                            AS MaxAnswerScore,
         MIN(a.Score)                            AS MinAnswerScore,
         MIN(a.CreationDate)                     AS FirstAnswerDate,
         MAX(a.CreationDate)                     AS LastAnswerDate,
         SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswers
  FROM answers a
  GROUP BY a.ParentId
),
postlink_agg AS (
  SELECT pl.PostId,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS OutgoingLinks,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
         MAX(pl.CreationDate)                       AS LastLinkDate
  FROM PostLinks pl
  GROUP BY pl.PostId
),
user_badges AS (
  SELECT b.UserId,
         COUNT(*)                           AS BadgeCount,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
         COUNT(DISTINCT CASE WHEN b.TagBased = B'1' THEN b.Name END) AS DistinctTagBadges,
         array_remove(array_agg(DISTINCT CASE WHEN b.TagBased = B'1' THEN b.Name END), NULL) AS TagBadges
  FROM Badges b
  GROUP BY b.UserId
),
user_activity_windows AS (
  SELECT u.Id                            AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views,
         row_number() OVER (ORDER BY u.Reputation DESC) AS GlobalReputationRank,
         rank() OVER (PARTITION BY date_trunc('year', u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRepRank
  FROM Users u
),
tag_stats AS (
  SELECT te.QuestionId,
         COUNT(*)                                AS TagCount,
         string_agg(DISTINCT te.Tag, '><')       AS TagsConcatenated,
         max(length(te.Tag))                     AS LongestTagLen,
         min(length(te.Tag))                     AS ShortestTagLen
  FROM tag_expansion te
  GROUP BY te.QuestionId
),
recent_hot_questions AS (
  SELECT q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
  FROM question_base q
  WHERE q.CreationDate >= now() - interval '90 days'
    AND q.Score >= 50
),
cold_questions AS (
  SELECT q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
  FROM question_base q
  WHERE (q.ViewCount IS NULL OR q.ViewCount < 10)
    AND (q.Score IS NULL OR q.Score <= 0)
),
combined_demo_set AS (
  SELECT * FROM recent_hot_questions
  UNION
  SELECT * FROM cold_questions
),
question_metrics AS (
  SELECT q.Id                                     AS QuestionId,
         coalesce(q.Title, '(no title)')         AS Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score                                   AS QuestionScore,
         q.ViewCount,
         aa.AnswerCount,
         aa.AvgAnswerScore,
         aa.MaxAnswerScore,
         aa.FirstAnswerDate,
         pa.OutgoingLinks,
         pa.DuplicateLinks,
         ts.TagCount,
         ts.TagsConcatenated,
         ub.BadgeCount,
         ub.GoldBadges,
         ub.SilverBadges,
         ub.BronzeBadges,
         uaw.Reputation                              AS OwnerReputation,
         uaw.GlobalReputationRank,
         CASE
           WHEN q.AcceptedAnswerId IS NOT NULL THEN 'accepted'
           WHEN aa.AnswerCount IS NULL THEN 'no-answers'
           WHEN aa.AnswerCount = 0 THEN 'no-answers'
           ELSE 'unaccepted'
         END                                        AS AcceptanceState,
         ntile(10) OVER (ORDER BY q.ViewCount DESC NULLS LAST) AS ViewDecile,
         length(coalesce(q.Title, ''))               AS TitleLength,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id)                 AS CommentCount,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVoteCount,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVoteCount,
         (SELECT SUM(coalesce(v.BountyAmount,0)) FROM Votes v WHERE v.PostId = q.Id) AS BountySum
  FROM question_base q
  LEFT JOIN answer_agg aa ON aa.QuestionId = q.Id
  LEFT JOIN postlink_agg pa ON pa.PostId = q.Id
  LEFT JOIN tag_stats ts ON ts.QuestionId = q.Id
  LEFT JOIN user_badges ub ON ub.UserId = q.OwnerUserId
  LEFT JOIN user_activity_windows uaw ON uaw.UserId = q.OwnerUserId
)
SELECT
  qm.QuestionId,
  -- Title and derived text metrics
  qm.Title,
  qm.TitleLength,
  qm.TagsConcatenated,
  qm.TagCount,
  qm.LongestTagLen,
  qm.ShortestTagLen,
  -- Q/A metrics
  qm.QuestionScore,
  qm.ViewCount,
  qm.ViewDecile,
  qm.AnswerCount,
  qm.AvgAnswerScore,
  qm.MaxAnswerScore,
  qm.FirstAnswerDate,
  qm.AcceptanceState,
  -- Links & votes & comments
  coalesce(qm.OutgoingLinks,0)                       AS OutgoingLinks,
  coalesce(qm.DuplicateLinks,0)                      AS DuplicateLinks,
  coalesce(qm.CommentCount,0)                        AS CommentCount,
  coalesce(qm.UpVoteCount,0) - coalesce(qm.DownVoteCount,0)    AS NetVotes,
  coalesce(qm.BountySum,0)                           AS TotalBounty,
  -- Owner info
  qm.OwnerUserId,
  qm.OwnerReputation,
  qm.GlobalReputationRank,
  qm.BadgeCount,
  qm.GoldBadges,
  qm.SilverBadges,
  qm.BronzeBadges,
  -- computed indicators using NULL logic and correlated checks
  CASE
    WHEN qm.OwnerUserId IS NULL THEN 'owned-by-anon'
    WHEN qm.OwnerReputation > 100000 THEN 'elite-owner'
    WHEN qm.OwnerReputation > 10000 THEN 'power-user'
    ELSE 'regular-owner'
  END                                                AS OwnerTier,
  (SELECT bool_or(b.Class = 1) FROM Badges b WHERE b.UserId = qm.OwnerUserId) AS OwnerHasGoldBadge,
  EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = qm.QuestionId AND a.Score >= qm.MaxAnswerScore AND a.CreationDate = (SELECT MIN(a2.CreationDate) FROM Posts a2 WHERE a2.ParentId = qm.QuestionId AND a2.Score = qm.MaxAnswerScore)) AS TopScoringAnswerIsEarliestMax,
  -- complex ratio and normalized metrics
  CASE WHEN qm.AnswerCount IS NULL OR qm.AnswerCount = 0 THEN NULL
       ELSE round((qm.AvgAnswerScore::numeric / NULLIF(qm.QuestionScore,0))::numeric,3)
  END                                               AS AvgAnswerScore_to_QuestionScore,
  -- correlated subquery with JSON-like aggregation (PostHistory heavy)
  (SELECT count(*) FROM PostHistory ph WHERE ph.PostId = qm.QuestionId AND ph.PostHistoryTypeId IN (4,5,6,24)) AS EditCount,
  (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = qm.QuestionId) AS LastHistoryDate,
  -- perform a correlated check for duplicates via PostLinks
  (SELECT count(*) FROM PostLinks pl2 WHERE pl2.PostId = qm.QuestionId AND pl2.LinkTypeId = 3) AS DuplicateCount,
  -- windowed popularity rank per owner
  row_number() OVER (PARTITION BY qm.OwnerUserId ORDER BY qm.ViewCount DESC NULLS LAST) AS OwnerQuestionRankByViews,
  -- include membership of demo combined set via EXCEPT/INTERSECT demonstration
  CASE WHEN qm.QuestionId IN (SELECT Id FROM combined_demo_set) THEN 'demo-set' ELSE 'regular' END AS DemoSetFlag
FROM question_metrics qm
LEFT JOIN tag_stats ts ON ts.QuestionId = qm.QuestionId
-- ensure we include some outer-joined computed attributes to stress planner
LEFT JOIN LATERAL (
  SELECT (array_agg(distinct lower(te.Tag)) FILTER (WHERE te.Tag IS NOT NULL))[1:5] AS TopFiveLowerTags
  FROM tag_expansion te
  WHERE te.QuestionId = qm.QuestionId
) ttop ON TRUE
WHERE
  -- complicated predicate combining NULL logic, correlated subselects and nested expressions
  (
    (qm.ViewCount IS NOT NULL AND qm.ViewCount > 100)
    OR
    (qm.AnswerCount IS NOT NULL AND qm.AnswerCount >= 3)
    OR
    (qm.OwnerReputation IS NOT NULL AND qm.OwnerReputation > 5000 AND qm.QuestionScore > 0)
    OR
    (qm.TagCount IS NOT NULL AND qm.TagCount >= 2 AND qm.TagsConcatenated ILIKE '%sql%')
  )
  AND NOT EXISTS (
    SELECT 1 FROM Posts p2 WHERE p2.ParentId = qm.QuestionId AND p2.Score < -5
  )
ORDER BY
  -- multi-level ordering with expressions and NULL handling
  (qm.AcceptanceState = 'accepted') DESC,
  qm.ViewDecile DESC NULLS LAST,
  coalesce(qm.AnswerCount,0) DESC,
  qm.QuestionScore DESC NULLS LAST,
  qm.QuestionId
LIMIT 100;