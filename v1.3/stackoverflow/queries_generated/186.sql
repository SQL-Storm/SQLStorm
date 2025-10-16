-- {"query": "186.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2984} 
WITH
-- explode tags from question posts into one row per tag
tag_explode AS (
  SELECT p.Id AS QuestionId,
         u.Id AS OwnerUserId,
         TRIM(t) AS TagName,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.FavoriteCount
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  CROSS JOIN LATERAL (
    -- Tags are stored like '<tag1><tag2>'; remove bounds then split
    SELECT regexp_split_to_table(
             COALESCE(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), ''), '><'
           ) AS t
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
-- per-question aggregated answer metrics (including correlated subquery for accepted/fast answers)
answer_agg AS (
  SELECT q.Id AS QuestionId,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCountTotal,
         SUM(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AnswerScoreSum,
         MAX(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AnswerScoreMax,
         MIN(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AnswerScoreMin,
         (SELECT a2.Id FROM Posts a2
          WHERE a2.ParentId = q.Id AND a2.PostTypeId = 2
          ORDER BY (a2.Score DESC NULLS LAST), a2.CreationDate ASC
          LIMIT 1) AS HighestScoringAnswerId,
         (SELECT a3.Id FROM Posts a3 WHERE a3.Id = q.AcceptedAnswerId) AS AcceptedAnswerId,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 5) AS FavoriteVotes -- may be null if feature removed
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.AcceptedAnswerId
),
-- per-user summary including badge counts and recency metrics
user_summary AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT b.Id) AS BadgeCount,
         COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
         COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
         COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
         MAX(u.LastAccessDate) AS LastAccess,
         SUM(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS PostsScoreSum,
         AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS PostsScoreAvg,
         -- latest badge by date (correlated)
         (SELECT b2.Name FROM Badges b2 WHERE b2.UserId = u.Id ORDER BY b2.Date DESC LIMIT 1) AS LatestBadge,
         (SELECT p2.Title FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 ORDER BY p2.CreationDate DESC LIMIT 1) AS LatestQuestionTitle
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
-- tag popularity and recent activity
tag_stats AS (
  SELECT te.TagName,
         COUNT(DISTINCT te.QuestionId) AS QuestionsWithTag,
         SUM(COALESCE(te.ViewCount,0)) AS TotalViews,
         SUM(COALESCE(te.Score,0)) AS TotalScore,
         MAX(te.CreationDate) AS MostRecentQuestion,
         MIN(te.CreationDate) AS OldestQuestion,
         AVG(COALESCE(te.Score,0)) AS AvgQuestionScore,
         -- top contributor for tag by number of questions
         (SELECT u.DisplayName FROM Users u
          WHERE u.Id = (
            SELECT te2.OwnerUserId FROM tag_explode te2
            WHERE te2.TagName = te.TagName
            GROUP BY te2.OwnerUserId
            ORDER BY COUNT(*) DESC NULLS LAST
            LIMIT 1
          )
         ) AS TopContributorDisplayName
  FROM tag_explode te
  GROUP BY te.TagName
),
-- combine question + answer aggregates + tags
question_enriched AS (
  SELECT q.Id,
         q.Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score AS QuestionScore,
         q.ViewCount,
         q.AnswerCount,
         q.FavoriteCount,
         COALESCE(a.AnswerCountTotal,0) AS AnswerCountTotal,
         COALESCE(a.AnswerScoreSum,0) AS AnswerScoreSum,
         a.HighestScoringAnswerId,
         a.AcceptedAnswerId,
         STRING_AGG(DISTINCT te.TagName, ',') FILTER (WHERE te.TagName IS NOT NULL) AS Tags
  FROM Posts q
  LEFT JOIN answer_agg a ON a.QuestionId = q.Id
  LEFT JOIN tag_explode te ON te.QuestionId = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount,
           a.AnswerCountTotal, a.AnswerScoreSum, a.HighestScoringAnswerId, a.AcceptedAnswerId
),
-- for performance: compute per-user top N answers by score using window functions
user_top_answers AS (
  SELECT ua.OwnerUserId AS UserId,
         ua.Id AS AnswerId,
         ua.ParentId AS QuestionId,
         ua.Score,
         RANK() OVER (PARTITION BY ua.OwnerUserId ORDER BY ua.Score DESC NULLS LAST, ua.CreationDate ASC) AS RankByScore,
         ROW_NUMBER() OVER (PARTITION BY ua.OwnerUserId ORDER BY ua.CreationDate DESC) AS MostRecentRank
  FROM Posts ua
  WHERE ua.PostTypeId = 2
),
-- users' best answers (top 3) aggregated into a JSON-like text
user_best_answers_agg AS (
  SELECT u.Id AS UserId,
         COALESCE(
           STRING_AGG(
             ('[' || uta.RankByScore || '|' || COALESCE(p.Title, 'Q#'||uta.QuestionId::text) || '->A#' || uta.AnswerId::text || '|' || COALESCE(uta.Score::text,'0') || ']'),
             ','
           ) FILTER (WHERE uta.RankByScore <= 3),
           ''
         ) AS TopAnswersSummary
  FROM Users u
  LEFT JOIN user_top_answers uta ON uta.UserId = u.Id
  LEFT JOIN Posts p ON p.Id = uta.QuestionId
  GROUP BY u.Id
),
-- combine user aggregates with tag popularity via full outer join to stress join logic
user_tag_combine AS (
  SELECT COALESCE(us.UserId, NULL) AS UserId,
         us.DisplayName,
         us.Reputation,
         us.BadgeCount,
         us.GoldBadges,
         us.SilverBadges,
         us.BronzeBadges,
         us.LatestBadge,
         usa.TopAnswersSummary,
         ts.TagName,
         ts.QuestionsWithTag,
         ts.TotalViews,
         ts.TotalScore
  FROM user_summary us
  FULL OUTER JOIN user_best_answers_agg usa ON usa.UserId = us.UserId
  FULL OUTER JOIN (
    -- attach the single most popular tag (by QuestionsWithTag) as synthetic row to force combining
    SELECT TagName, QuestionsWithTag, TotalViews, TotalScore
    FROM tag_stats
    WHERE TagName IS NOT NULL
    ORDER BY QuestionsWithTag DESC NULLS LAST
    LIMIT 100
  ) ts ON 1=1 -- cross join-like behavior; full outer preserved by previous
),
-- create complex predicate filters and computed ranks using set operators to mix results
filtered_users AS (
  -- users with either high reputation or many badges but exclude those who are both low rep and low badges
  SELECT UserId, DisplayName, Reputation, BadgeCount, GoldBadges, SilverBadges, BronzeBadges, LatestBadge, TopAnswersSummary, TagName, QuestionsWithTag, TotalViews, TotalScore
  FROM user_tag_combine
  WHERE (Reputation >= 10000 OR BadgeCount >= 50)
    AND NOT (COALESCE(Reputation,0) < 100 AND COALESCE(BadgeCount,0) < 5)
  UNION
  -- include some medium users who have high-scoring answers (set operator branch)
  SELECT utc.UserId, utc.DisplayName, utc.Reputation, utc.BadgeCount, utc.GoldBadges, utc.SilverBadges, utc.BronzeBadges, utc.LatestBadge, utc.TopAnswersSummary, utc.TagName, utc.QuestionsWithTag, utc.TotalViews, utc.TotalScore
  FROM user_tag_combine utc
  WHERE EXISTS (
    SELECT 1 FROM user_top_answers uta WHERE uta.UserId = utc.UserId AND uta.RankByScore = 1 AND uta.Score >= 50
  )
)
-- final select: combine stats, include correlated scalar subqueries, windowed ranks and complicated expressions
SELECT fu.UserId,
       COALESCE(fu.DisplayName, 'unknown') AS DisplayName,
       COALESCE(fu.Reputation, 0) AS Reputation,
       COALESCE(fu.BadgeCount, 0) AS BadgeCount,
       COALESCE(fu.GoldBadges,0) AS GoldBadges,
       COALESCE(fu.SilverBadges,0) AS SilverBadges,
       COALESCE(fu.BronzeBadges,0) AS BronzeBadges,
       fu.LatestBadge,
       LEFT(COALESCE(fu.TopAnswersSummary,''), 400) AS TopAnswersSnippet,
       fu.TagName,
       COALESCE(fu.QuestionsWithTag,0) AS QuestionsWithTag,
       COALESCE(fu.TotalViews,0) AS TotalTagViews,
       COALESCE(fu.TotalScore,0) AS TotalTagScore,
       -- correlated scalar: count of distinct tags used by user in their questions
       (SELECT COUNT(DISTINCT te.TagName) FROM tag_explode te WHERE te.OwnerUserId = fu.UserId) AS DistinctTagsUsed,
       -- correlated scalar: average answer score for this user's answers
       (SELECT AVG(a.Score) FROM Posts a WHERE a.OwnerUserId = fu.UserId AND a.PostTypeId = 2) AS AvgAnswerScore,
       -- window function to rank users by reputation within this resultset (dense rank)
       DENSE_RANK() OVER (ORDER BY COALESCE(fu.Reputation,0) DESC) AS RankByReputation,
       -- composite popularity score with NULL logic and non-linear scaling
       ROUND(
         (COALESCE(fu.Reputation,0)::numeric / NULLIF(GREATEST(COALESCE(fu.QuestionsWithTag,0),1),0)) * 0.6
         + (LEAST(1000, COALESCE(fu.TotalTagViews,0))::numeric / 1000) * 0.2
         + (LEAST(100, COALESCE(fu.TotalTagScore,0))::numeric / 100) * 0.2
         + (COALESCE(fu.BadgeCount,0)::numeric / NULLIF(GREATEST(COALESCE(fu.Reputation,0),1),1)) * 10
       ,2) AS CompositePopularity,
       -- string expression mixing fields with NULL-safe formatting
       CASE
         WHEN fu.TagName IS NULL THEN 'NoTag'
         ELSE fu.TagName || ' (' || COALESCE(fu.QuestionsWithTag::text,'0') || ' q)'
       END AS TagSummary,
       -- complicated boolean logic producing a human-readable status flag
       CASE
         WHEN COALESCE(fu.Reputation,0) >= 50000 AND COALESCE(fu.GoldBadges,0) >= 5 THEN 'Legend'
         WHEN COALESCE(fu.Reputation,0) >= 10000 OR COALESCE(fu.BadgeCount,0) >= 50 THEN 'Established'
         WHEN COALESCE(fu.Reputation,0) >= 1000 OR COALESCE(fu.BadgeCount,0) >= 10 THEN 'Rising'
         ELSE 'New'
       END AS StatusFlag
FROM filtered_users fu
-- exclude purely null user rows that can come from full outer joins
WHERE fu.UserId IS NOT NULL
ORDER BY CompositePopularity DESC NULLS LAST, RankByReputation ASC
LIMIT 200;