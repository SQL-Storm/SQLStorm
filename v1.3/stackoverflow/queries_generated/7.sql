-- {"query": "7.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2629} 
WITH
-- recent active posts with parsed tag arrays and basic metrics
RecentQuestions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         COALESCE(p.AnswerCount,0) AS AnswerCount,
         COALESCE(p.FavoriteCount,0) AS FavoriteCount,
         NULLIF(TRIM(p.Tags),'') AS RawTags,
         -- split tags stored as like '<tag1><tag2>' into array; adapt to engines with string_to_array/substr
         CASE
           WHEN p.Tags IS NULL THEN ARRAY[]::varchar[]
           ELSE string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')
         END AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),

-- compute per-question aggregated signals: recent comments, last edit, duplicate links, and hottest answer stats
QuestionSignals AS (
  SELECT q.*,
         COALESCE(c.RecentComments,0) AS RecentComments,
         ph.LastEditDate,
         pl.DuplicateCount,
         a.BestAnswerScore,
         a.BestAnswerAgeHours,
         -- a complex synthetic popularity score mixing many signals, intentionally non-linear
         (COALESCE(q.Score,0) * 1.5
          + ln(GREATEST(q.ViewCount,1)) * 2.1
          + COALESCE(q.FavoriteCount,0) * 3
          + COALESCE(c.RecentComments,0) * 0.8
          + COALESCE(a.BestAnswerScore,0) * 2.5
          - (COALESCE(ph.DaySinceEdit,365) / 365.0) * 1.2
          + (CASE WHEN pl.DuplicateCount>0 THEN -5 ELSE 0 END)
         )::numeric(12,4) AS PopularityScore
  FROM RecentQuestions q
  LEFT JOIN (
    SELECT PostId, COUNT(*) FILTER (WHERE CreationDate >= now() - interval '90 days') AS RecentComments
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = q.Id
  LEFT JOIN (
    SELECT ph.PostId,
           MAX(ph.CreationDate) AS LastEditDate,
           EXTRACT(epoch FROM (now() - MAX(ph.CreationDate)))/86400.0 AS DaySinceEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,24) -- edit types
    GROUP BY ph.PostId
  ) ph ON ph.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount
    FROM PostLinks
    WHERE LinkTypeId IN (1,3)
    GROUP BY PostId
  ) pl ON pl.PostId = q.Id
  LEFT JOIN (
    -- for each question, find the highest-scoring answer and how old it is
    SELECT a.ParentId AS QuestionId,
           MAX(a.Score) AS BestAnswerScore,
           MIN(EXTRACT(epoch FROM (now() - a.CreationDate))/3600.0) AS BestAnswerAgeHours
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
  ) a ON a.QuestionId = q.Id
),

-- top users signals: reputation, badge-weighted score, recency of activity
UserSignals AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views AS ProfileViews,
         COALESCE(b.BadgeScore,0) AS BadgeScore,
         -- recency weight decays with time since last access
         EXP(-GREATEST(EXTRACT(epoch FROM (now() - u.LastAccessDate))/86400.0,0)/180.0) AS RecencyWeight
  FROM Users u
  LEFT JOIN (
    SELECT UserId,
           SUM(CASE WHEN Class=1 THEN 5 WHEN Class=2 THEN 2 WHEN Class=3 THEN 1 ELSE 0 END) AS BadgeScore
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  WHERE u.Reputation > 100
),

-- map questions to their top answerer(s) and compute contributor influence
QuestionContributors AS (
  SELECT q.Id AS QuestionId,
         q.OwnerUserId AS AskerId,
         ua.AnswererId,
         ua.AnswersByUser,
         ua.AvgScoreByUser,
         ua.FirstAnswerAgeHours,
         us.Reputation AS AnswererReputation,
         us.BadgeScore AS AnswererBadgeScore,
         -- contributor influence: combine counts, avg score, and reputation with a null-safe formula
         (COALESCE(ua.AnswersByUser,0) * 0.6
          + COALESCE(ua.AvgScoreByUser,0) * 1.8
          + COALESCE(us.Reputation,0) / 1000.0
          + COALESCE(us.BadgeScore,0) * 0.3
         )::numeric(10,4) AS ContributorInfluence
  FROM RecentQuestions q
  LEFT JOIN (
    SELECT a.ParentId AS QuestionId,
           a.OwnerUserId AS AnswererId,
           COUNT(*) FILTER (WHERE a.OwnerUserId IS NOT NULL) OVER (PARTITION BY a.ParentId, a.OwnerUserId) AS AnswersByUser,
           AVG(a.Score) OVER (PARTITION BY a.ParentId, a.OwnerUserId) AS AvgScoreByUser,
           MIN(EXTRACT(epoch FROM (now() - a.CreationDate))/3600.0) OVER (PARTITION BY a.ParentId, a.OwnerUserId) AS FirstAnswerAgeHours
    FROM Posts a
    WHERE a.PostTypeId = 2
  ) ua ON ua.QuestionId = q.Id
  LEFT JOIN UserSignals us ON us.UserId = ua.AnswererId
),

-- tags enrichment: expand tags into rows and compute tag-level aggregates
TagExplode AS (
  SELECT qs.Id AS QuestionId,
         unnest(qs.TagArray) AS Tag
  FROM RecentQuestions qs
),
TagAgg AS (
  SELECT te.Tag,
         COUNT(DISTINCT te.QuestionId) AS QuestionCount,
         SUM(qs.ViewCount) AS TotalViews,
         AVG(qs.Score) AS AvgScore,
         MAX(qs.CreationDate) AS MostRecentQuestion
  FROM TagExplode te
  JOIN RecentQuestions qs ON qs.Id = te.QuestionId
  GROUP BY te.Tag
),

-- final selection: combine everything, include correlated subqueries and window functions
FinalCandidates AS (
  SELECT qs.Id AS QuestionId,
         qs.Title,
         qs.OwnerUserId,
         qs.CreationDate,
         qs.Score,
         qs.ViewCount,
         qs.AnswerCount,
         qs.FavoriteCount,
         qs.TagArray,
         qs.RecentComments,
         qs.LastEditDate,
         qs.DuplicateCount,
         qs.BestAnswerScore,
         qs.BestAnswerAgeHours,
         qs.PopularityScore,
         -- top contributor per question via window
         qc.AnswererId AS TopAnswererId,
         qc.AnswersByUser,
         qc.AvgScoreByUser,
         qc.AnswererReputation,
         qc.ContributorInfluence,
         -- compute tag-based hotness using correlated subquery (prefers tags with recent activity)
         (
           SELECT STRING_AGG(t.Tag || ':' || COALESCE(ROUND( (ta.QuestionCount::numeric * 0.5 + ta.TotalViews::numeric / NULLIF(GREATEST(ta.QuestionCount,1),1) * 0.0001 + EXTRACT(epoch FROM (now() - ta.MostRecentQuestion))/86400.0 * (-0.01) ),2)::text,'|')
           FROM (
             SELECT te.Tag,
                    COUNT(DISTINCT te.QuestionId) AS QuestionCount,
                    SUM(rq.ViewCount) AS TotalViews,
                    AVG(rq.Score) AS AvgScore,
                    MAX(rq.CreationDate) AS MostRecentQuestion
             FROM TagExplode te
             JOIN RecentQuestions rq ON rq.Id = te.QuestionId
             WHERE te.Tag = ANY(qs.TagArray)
             GROUP BY te.Tag
             ORDER BY QuestionCount DESC NULLS LAST
             LIMIT 5
           ) ta
           JOIN (SELECT Tag FROM Tags) t ON t.TagName = ta.Tag
         ) AS TagHotnessSummary,
         -- window ranking across popularity partitions (dense_rank)
         DENSE_RANK() OVER (ORDER BY qs.PopularityScore DESC NULLS LAST) AS GlobalPopularityRank,
         -- percentile within tags: compute average rank across tags for question
         (
           SELECT AVG(tp.rnk)::numeric(10,4)
           FROM (
             SELECT q2.Id,
                    NTILE(10) OVER (ORDER BY q2.PopularityScore DESC) AS rnk
             FROM TagExplode te2
             JOIN RecentQuestions q2 ON q2.Id = te2.QuestionId
             WHERE te2.Tag = ANY(qs.TagArray)
           ) tp
         ) AS TagPercentileBucketAvg,
         -- combined heuristic score with null-aware coalesce and conditional boosts
         (
           qs.PopularityScore
           + COALESCE(qc.ContributorInfluence,0) * 2.2
           + (CASE WHEN qc.AnswererId IS NOT NULL AND qs.AcceptedAnswerId IS NOT NULL THEN 4 ELSE 0 END)
           + (CASE WHEN qs.DuplicateCount > 0 THEN -6 ELSE 0 END)
         ) * (1 + COALESCE((SELECT AVG(u.RecencyWeight) FROM UserSignals u WHERE u.UserId = qs.OwnerUserId), 0)) AS HeuristicScore
  FROM QuestionSignals qs
  LEFT JOIN (
    SELECT DISTINCT ON (QuestionId) *
    FROM QuestionContributors
    ORDER BY QuestionId, ContributorInfluence DESC NULLS LAST, AnswererReputation DESC NULLS LAST
  ) qc ON qc.QuestionId = qs.Id
)

SELECT
  fc.QuestionId,
  LEFT(fc.Title, 200) AS SnippetTitle,
  fc.OwnerUserId,
  u.DisplayName AS OwnerName,
  COALESCE(u.Reputation,0) AS OwnerReputation,
  fc.CreationDate,
  fc.Score,
  fc.ViewCount,
  fc.AnswerCount,
  fc.RecentComments,
  fc.BestAnswerScore,
  fc.LastEditDate,
  fc.DuplicateCount,
  fc.TagHotnessSummary,
  fc.TopAnswererId,
  fc.AnswererReputation,
  fc.ContributorInfluence,
  fc.GlobalPopularityRank,
  fc.TagPercentileBucketAvg,
  ROUND(fc.PopularityScore::numeric,4) AS PopularityScore,
  ROUND(fc.HeuristicScore::numeric,4) AS HeuristicScore,
  -- include an existence check and correlated scalar subquery to fetch the body length of the accepted answer if present
  CASE WHEN EXISTS (SELECT 1 FROM Posts pa WHERE pa.Id = (SELECT p.AcceptedAnswerId FROM Posts p WHERE p.Id = fc.QuestionId)) THEN
       (SELECT char_length(pa.Body) FROM Posts pa WHERE pa.Id = (SELECT p.AcceptedAnswerId FROM Posts p WHERE p.Id = fc.QuestionId))
  ELSE NULL END AS AcceptedAnswerBodyLength,
  -- compute a JSON-like string of top 3 tags with their global tag counts (string manipulation + null logic)
  (SELECT STRING_AGG(t.TagName || '=' || COALESCE(t.Count::text,'0'), ',')
   FROM Tags t
   WHERE t.TagName = ANY(fc.TagArray)
   ORDER BY t.Count DESC NULLS LAST
   LIMIT 3
  ) AS TopTagsCounts
FROM FinalCandidates fc
LEFT JOIN Users u ON u.Id = fc.OwnerUserId
WHERE fc.PopularityScore IS NOT NULL
  AND fc.PopularityScore > (
    SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY qs2.PopularityScore) FROM QuestionSignals qs2
  )
ORDER BY fc.HeuristicScore DESC NULLS LAST, fc.GlobalPopularityRank ASC
LIMIT 250;