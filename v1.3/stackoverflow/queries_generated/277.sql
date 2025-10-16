-- {"query": "277.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3738} 
WITH
-- recent posts in the last year
recent_posts AS (
  SELECT *
  FROM Posts
  WHERE CreationDate >= now() - interval '365 days'
),
-- normalize tags into rows (tags stored as '<a><b>')
post_tags AS (
  SELECT p.Id AS PostId,
         lower(trim(t.tag)) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  ) t
  WHERE p.Tags IS NOT NULL
),
-- popularity & statistics per tag (using all posts)
tag_stats AS (
  SELECT pt.Tag,
         count(DISTINCT p.Id)                                    AS PostCount,
         avg(p.Score)                                             AS AvgScore,
         sum(COALESCE(p.ViewCount,0))                             AS TotalViews,
         sum(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)        AS Questions,
         sum(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)        AS Answers,
         rank() OVER (ORDER BY count(DISTINCT p.Id) DESC)        AS PopularRank
  FROM post_tags pt
  JOIN Posts p ON p.Id = pt.PostId
  GROUP BY pt.Tag
),
-- per-user aggregated post metrics (questions & answers, avg scores, views)
user_post_agg AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         COUNT(p.Id)                                                   AS TotalPosts,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)             AS QuestionCount,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)             AS AnswerCount,
         AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)              AS AvgQuestionScore,
         AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)              AS AvgAnswerScore,
         SUM(COALESCE(p.ViewCount,0))                                  AS SumViews,
         MAX(p.LastActivityDate)                                       AS LastPostActivity,
         -- correlated subquery: number of this user's answers that have been accepted
         (
           SELECT COUNT(1)
           FROM Posts a
           JOIN Posts q ON q.AcceptedAnswerId = a.Id
           WHERE a.OwnerUserId = u.Id
         )                                                               AS AcceptedAnswers,
         -- last edit time by this user (could be on any post)
         (
           SELECT MAX(LastEditDate)
           FROM Posts p2
           WHERE p2.LastEditorUserId = u.Id
         )                                                               AS LastEditByUser,
         -- last comment text by this user (excerpt)
         (
           SELECT substring(c.Text FROM 1 FOR 120)
           FROM Comments c
           WHERE c.UserId = u.Id
           ORDER BY c.CreationDate DESC
           LIMIT 1
         )                                                               AS LastCommentExcerpt
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
-- aggregate votes per user (via posts they own)
user_vote_agg AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(v.Id)                                                       AS VotesReceived,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 2)                           AS UpVotesReceived,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 3)                           AS DownVotesReceived,
         SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyReceived
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
),
-- badge-derived score per user (weights: Gold=5, Silver=3, Bronze=1; tag-based add 0.5)
badge_scores AS (
  SELECT b.UserId,
         SUM(CASE b.Class WHEN 1 THEN 5 WHEN 2 THEN 3 WHEN 3 THEN 1 ELSE 0 END) +
         SUM(CASE WHEN b.TagBased = 1 THEN 0.5 ELSE 0 END)                   AS BadgeScore,
         COUNT(*)                                                             AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
-- number of times user's posts were marked duplicate or linked away (via PostLinks)
duplicate_and_link_stats AS (
  SELECT p.OwnerUserId AS UserId,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END)                 AS DuplicateLinksOut,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END)                 AS LinkedOut
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.PostId
  GROUP BY p.OwnerUserId
),
-- users' top tag by count (tie-breaker: higher avg score)
user_tag_affinity AS (
  SELECT ut.UserId, ut.Tag, ut.TagCount, ut.AvgTagScore,
         row_number() OVER (PARTITION BY ut.UserId ORDER BY ut.TagCount DESC, ut.AvgTagScore DESC, ut.Tag) AS rn
  FROM (
    SELECT p.OwnerUserId AS UserId,
           lower(trim(t.tag)) AS Tag,
           COUNT(*) AS TagCount,
           AVG(p.Score) AS AvgTagScore
    FROM Posts p
    JOIN LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag
    ) t ON p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, lower(trim(t.tag))
  ) ut
),
top_user_tag AS (
  SELECT UserId, Tag AS TopTag, TagCount AS TopTagCount, AvgTagScore AS TopTagAvgScore
  FROM user_tag_affinity
  WHERE rn = 1
),
-- active and veteran sets (demonstrate set operators)
active_users AS (
  SELECT Id AS UserId FROM Users WHERE LastAccessDate >= now() - interval '90 days'
),
veteran_users AS (
  SELECT Id AS UserId FROM Users WHERE CreationDate <= now() - interval '3650 days' -- ~10 years
),
active_not_veteran AS (
  SELECT UserId FROM active_users
  EXCEPT
  SELECT UserId FROM veteran_users
),
-- create a unified user summary with many joins and NULL-safe calculations
user_summary AS (
  SELECT u.UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.TotalPosts,
         COALESCE(u.QuestionCount,0) AS QuestionCount,
         COALESCE(u.AnswerCount,0)   AS AnswerCount,
         ROUND(COALESCE(u.AvgQuestionScore,0)::numeric,2) AS AvgQuestionScore,
         ROUND(COALESCE(u.AvgAnswerScore,0)::numeric,2)   AS AvgAnswerScore,
         COALESCE(v.VotesReceived,0) AS VotesReceived,
         COALESCE(v.UpVotesReceived,0) AS UpVotesReceived,
         COALESCE(v.DownVotesReceived,0) AS DownVotesReceived,
         COALESCE(b.BadgeScore,0)    AS BadgeScore,
         COALESCE(b.BadgeCount,0)    AS BadgeCount,
         COALESCE(d.DuplicateLinksOut,0) AS DuplicateLinksOut,
         COALESCE(d.LinkedOut,0) AS LinkedOut,
         COALESCE(a.TopTag,'(none)') AS TopTag,
         COALESCE(a.TopTagCount,0) AS TopTagCount,
         COALESCE(a.TopTagAvgScore,0) AS TopTagAvgScore,
         COALESCE(u.AcceptedAnswers,0) AS AcceptedAnswers,
         COALESCE(u.SumViews,0) AS SumViews,
         u.LastPostActivity,
         u.LastEditByUser,
         u.LastCommentExcerpt,
         -- composite "influence" index with NULL logic and safe division
         (
           (COALESCE(u.TotalPosts,0) * 0.35)
           + (COALESCE(u.Reputation,0) * 0.25)
           + (COALESCE(b.BadgeScore,0) * 4)
           + (LOG(GREATEST(1, COALESCE(u.SumViews,0))) * 0.5)
           + (COALESCE(v.UpVotesReceived,0) - COALESCE(v.DownVotesReceived,0)) * 0.2
         ) / NULLIF((EXTRACT(EPOCH FROM (now() - COALESCE(u.CreationDate, now()))) / 86400.0)::numeric + 1, 0) AS InfluenceIndex
  FROM user_post_agg u
  LEFT JOIN user_vote_agg v ON v.UserId = u.UserId
  LEFT JOIN badge_scores b ON b.UserId = u.UserId
  LEFT JOIN duplicate_and_link_stats d ON d.UserId = u.UserId
  LEFT JOIN top_user_tag a ON a.UserId = u.UserId
),
-- rank and window analytics for benchmarking heavy window function usage
ranked_users AS (
  SELECT us.*,
         row_number() OVER (ORDER BY InfluenceIndex DESC NULLS LAST, Reputation DESC) AS GlobalRank,
         dense_rank() OVER (ORDER BY COALESCE(QuestionCount,0) DESC) AS QuestionRank,
         ntile(100) OVER (ORDER BY InfluenceIndex DESC NULLS LAST) AS InfluencePercentile,
         lag(InfluenceIndex) OVER (ORDER BY InfluenceIndex DESC NULLS LAST) AS PrevInfluence,
         lead(InfluenceIndex) OVER (ORDER BY InfluenceIndex DESC NULLS LAST) AS NextInfluence,
         CASE
           WHEN PrevInfluence IS NULL THEN NULL
           WHEN PrevInfluence = 0 THEN NULL
           ELSE ROUND( (InfluenceIndex - PrevInfluence) / NULLIF(ABS(PrevInfluence),0)::numeric * 100, 2)
         END AS PctChangeFromPrev
  FROM user_summary us
),
-- final set for diagnostics: active but not veteran users joined to ranked info
active_non_veterans_diagnostic AS (
  SELECT ru.*
  FROM ranked_users ru
  JOIN active_not_veteran anv ON anv.UserId = ru.UserId
)
-- final output: combine multiple facets using union all (set operator) to exercise engine
SELECT 'TOP_USERS_BY_INFLUENCE' AS ReportSection, ru.UserId, ru.DisplayName, ru.Reputation, ru.InfluenceIndex, ru.GlobalRank, ru.TopTag, ru.TopTagCount, ru.BadgeCount, ru.VotesReceived, ru.SumViews, ru.LastCommentExcerpt
FROM ranked_users ru
WHERE ru.GlobalRank <= 50

UNION ALL

SELECT 'ACTIVE_NON_VETERANS_SAMPLE' AS ReportSection, ad.UserId, ad.DisplayName, ad.Reputation, ad.InfluenceIndex, ad.GlobalRank, ad.TopTag, ad.TopTagCount, ad.BadgeCount, ad.VotesReceived, ad.SumViews, ad.LastCommentExcerpt
FROM active_non_veterans_diagnostic ad
ORDER BY ReportSection, InfluenceIndex DESC NULLS LAST, GlobalRank
LIMIT 200;