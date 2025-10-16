-- {"query": "115.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 3042} 
WITH
-- recent questions with parsed tags
recent_q AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         p.AnswerCount, p.FavoriteCount, p.Tags,
         COALESCE(p.LastActivityDate, p.LastEditDate, p.CreationDate) AS LastActivity,
         -- parse tags into array (Tags stored like '<tag1><tag2>')
         CASE WHEN p.Tags IS NULL THEN ARRAY[]::varchar[] ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '5 years'
),
-- explode tags for tag-level metrics
question_tags AS (
  SELECT q.Id AS QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, t.tag AS Tag
  FROM recent_q q
  LEFT JOIN LATERAL unnest(q.TagArray) WITH ORDINALITY AS t(tag, ord) ON true
),
-- aggregate tag popularity and question metrics
tag_agg AS (
  SELECT Tag,
         count(*) FILTER (WHERE QuestionId IS NOT NULL) AS QuestionsInWindow,
         avg(Score)::numeric(10,4) AS AvgQuestionScore,
         sum(ViewCount) AS TotalViews,
         median(ViewCount) OVER ()::bigint AS DummyMedian -- dummy to stress planner (ignored later)
  FROM question_tags
  GROUP BY Tag
),
-- compute per-question first answer time, best answer score, and average answer score (correlated subqueries)
question_answer_stats AS (
  SELECT q.Id AS QuestionId,
         q.CreationDate AS QuestionCreated,
         -- first answer creation
         (SELECT min(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS FirstAnswerCreated,
         -- best answer score
         (SELECT max(a.Score) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS BestAnswerScore,
         -- avg answer score, null if none
         (SELECT CASE WHEN count(*)=0 THEN NULL ELSE avg(a.Score) END FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
         -- number of distinct answerers
         (SELECT count(DISTINCT a.OwnerUserId) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS DistinctAnswerers,
         -- whether accepted answer exists and its score
         (SELECT a.Score FROM Posts a WHERE a.Id = q.AcceptedAnswerId AND q.AcceptedAnswerId IS NOT NULL LIMIT 1) AS AcceptedAnswerScore
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - interval '5 years'
),
-- compute user-level aggregates and dense ranking
user_stats AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.CreationDate,
         count(distinct p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
         count(distinct p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
         sum(vt_vote.upvotes) AS TotalUpvotesReceived,
         coalesce(badges.Gold,0) AS GoldBadges,
         coalesce(badges.Silver,0) AS SilverBadges,
         coalesce(badges.Bronze,0) AS BronzeBadges,
         -- activity recency
         greatest(u.LastAccessDate, u.CreationDate) AS LastSeen,
         row_number() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank,
         dense_rank() OVER (ORDER BY coalesce(badges.Gold,0) DESC, coalesce(badges.Silver,0) DESC, coalesce(badges.Bronze,0) DESC) AS BadgeRank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    -- pre-aggregate votes received for user's posts (upvotes only)
    SELECT p.OwnerUserId AS OwnerUserId, count(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
  ) vt_vote ON vt_vote.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId,
           SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END) AS Gold,
           SUM(CASE WHEN Class=2 THEN 1 ELSE 0 END) AS Silver,
           SUM(CASE WHEN Class=3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges
    GROUP BY UserId
  ) badges ON badges.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, vt_vote.upvotes, badges.Gold, badges.Silver, badges.Bronze
),
-- rank answers per question using window functions and compute lead/lag score diffs
ranked_answers AS (
  SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.OwnerUserId, a.CreationDate AS AnswerCreated, a.Score AS AnswerScore,
         row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS RankByScore,
         rank() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate ASC) AS ChronoRank,
         lag(a.Score) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS PrevScore,
         lead(a.Score) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS NextScore
  FROM Posts a
  WHERE a.PostTypeId = 2
),
-- compute per-question composite score for benchmarking (mix of views, scores, answers, recency)
question_composite AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         qa.FirstAnswerCreated,
         qa.BestAnswerScore,
         qa.AvgAnswerScore,
         -- composite: weighted sum with NULL handling
         (
           coalesce(q.Score,0) * 3
           + coalesce(q.ViewCount,0)::numeric / GREATEST(NULLIF(EXTRACT(EPOCH FROM (now() - q.CreationDate)),0),1) * 100.0
           + coalesce(qa.BestAnswerScore,0) * 5
           + coalesce(qa.AvgAnswerScore,0) * 2
           + coalesce(q.FavoriteCount,0) * 4
         ) AS CompositeScore,
         -- age in days
         EXTRACT(epoch FROM (now() - q.CreationDate))/86400.0 AS AgeDays
  FROM Posts q
  LEFT JOIN question_answer_stats qa ON qa.QuestionId = q.Id
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - interval '5 years'
),
-- heavy correlated correlated_sub which computes per-tag high-water mark of composite score (correlated)
tag_highwater AS (
  SELECT DISTINCT t.Tag,
         (SELECT max(qc.CompositeScore)
          FROM question_composite qc
          JOIN recent_q rq ON rq.Id = qc.QuestionId
          WHERE rq.TagArray IS NOT NULL AND rq.TagArray && ARRAY[t.Tag] ) AS MaxCompositeForTag,
         (SELECT count(*) FROM question_tags qt WHERE qt.Tag = t.Tag AND qt.AnswerCount = 0) AS ZeroAnswerQuestions
  FROM question_tags t
),
-- combine top contributors per tag using JOINs, outer joins, and EXISTS
top_contributors AS (
  SELECT tt.Tag, us.UserId, us.DisplayName, us.Reputation, us.QuestionsPosted, us.AnswersPosted, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
         -- contributor score: simple heuristic
         (coalesce(us.AnswersPosted,0) * 2 + coalesce(us.QuestionsPosted,0) * 1 + coalesce(us.GoldBadges,0)*5 + coalesce(us.Reputation,0)/1000.0) AS ContributorScore,
         row_number() OVER (PARTITION BY tt.Tag ORDER BY (coalesce(us.AnswersPosted,0)*2 + coalesce(us.GoldBadges,0)*5 + coalesce(us.Reputation,0)/1000.0) DESC) AS TagContributorRank
  FROM (
    SELECT DISTINCT Tag FROM question_tags
  ) tt
  LEFT JOIN Posts p ON p.PostTypeId = 2 -- answers
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN user_stats us ON us.UserId = u.Id
  LEFT JOIN question_tags qt ON qt.QuestionId = p.ParentId AND qt.Tag = tt.Tag
  WHERE qt.Tag IS NOT NULL
),
-- union set: combine recent high composite questions and legacy popular questions for comparison
union_questions AS (
  SELECT qc.QuestionId, qc.Title, qc.CompositeScore, qc.AgeDays, 'recent'::varchar AS cohort FROM question_composite qc
  WHERE qc.CompositeScore IS NOT NULL
  UNION ALL
  SELECT p.Id AS QuestionId, p.Title, (p.Score * 3 + p.ViewCount / GREATEST(EXTRACT(EPOCH FROM (now() - p.CreationDate)),1) * 50)::numeric AS CompositeScore, EXTRACT(epoch FROM (now() - p.CreationDate))/86400.0 AS AgeDays, 'legacy'::varchar
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.CreationDate < now() - interval '5 years' AND p.ViewCount > 10000
),
-- final selection windowed to compute percentiles and filters
final_ranked AS (
  SELECT uq.*, tt.MaxCompositeForTag, th.ZeroAnswerQuestions,
         row_number() OVER (PARTITION BY uq.cohort ORDER BY uq.CompositeScore DESC NULLS LAST) AS CohortRank,
         nt.Tag
  FROM union_questions uq
  LEFT JOIN recent_q rq ON rq.Id = uq.QuestionId
  LEFT JOIN question_tags nt ON nt.QuestionId = uq.QuestionId
  LEFT JOIN tag_highwater tt ON tt.Tag = nt.Tag
  LEFT JOIN tag_highwater th ON th.Tag = nt.Tag
)
SELECT DISTINCT
  fr.QuestionId,
  fr.Title,
  fr.cohort,
  fr.CompositeScore,
  fr.AgeDays::numeric(10,2) AS AgeDays,
  fr.CohortRank,
  fr.Tag,
  fr.MaxCompositeForTag,
  fr.ZeroAnswerQuestions,
  -- correlated subquery to fetch top 1 answerer for the question by score
  (SELECT u.DisplayName
   FROM Posts a
   LEFT JOIN Users u ON u.Id = a.OwnerUserId
   WHERE a.ParentId = fr.QuestionId AND a.PostTypeId = 2
   ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
   LIMIT 1) AS TopAnswererDisplayName,
  -- boolean existence checks with NULL logic
  EXISTS(SELECT 1 FROM Votes v WHERE v.PostId = fr.QuestionId AND v.VoteTypeId = 5) AS HasFavorites,
  CASE WHEN fr.MaxCompositeForTag IS NULL THEN 0 ELSE (fr.CompositeScore / GREATEST(fr.MaxCompositeForTag,1)) END AS RelativeToTagMax,
  -- string ops: truncated title and a fingerprint hash-ish expression
  left(coalesce(fr.Title, '<no-title>'), 120) AS ShortTitle,
  md5(coalesce(fr.Title, '') || '|' || coalesce(fr.Tag,'<notag>') || '|' || coalesce(fr.cohort,'')) AS TitleTagHash,
  -- include sample of top contributors for the tag (comma separated), using subquery with string_agg and NULL-safe logic
  (SELECT string_agg(distinct coalesce(u.DisplayName,'[deleted]') || ':' || us.ContributorScore::text, ', ' ORDER BY us.ContributorScore DESC)
   FROM top_contributors us
   LEFT JOIN Users u ON u.Id = us.UserId
   WHERE us.Tag = fr.Tag AND us.TagContributorRank <= 5
  ) AS TopContributorsForTag
FROM final_ranked fr
-- filter crucible: only tags with at least 5 questions in window OR composite in top 100 across cohorts
LEFT JOIN tag_agg ta ON ta.Tag = fr.Tag
WHERE (ta.QuestionsInWindow >= 5)
   OR fr.CohortRank <= 100
ORDER BY fr.CohortRank, fr.CompositeScore DESC
LIMIT 100;