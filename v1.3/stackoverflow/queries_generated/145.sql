-- {"query": "145.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2680} 
WITH
-- recent activity per post: last comment, last vote, last history
recent_activity AS (
  SELECT p.Id AS PostId,
         GREATEST(
           COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01'),
           COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01'),
           COALESCE(MAX(ph.CreationDate), TIMESTAMP '1970-01-01'),
           COALESCE(p.LastActivityDate, TIMESTAMP '1970-01-01')
         ) AS LastActivity,
         MAX(c.CreationDate) FILTER (WHERE c.Id IS NOT NULL) AS LastCommentDate,
         MAX(v.CreationDate) FILTER (WHERE v.Id IS NOT NULL) AS LastVoteDate,
         MAX(ph.CreationDate) FILTER (WHERE ph.Id IS NOT NULL) AS LastHistoryDate
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  GROUP BY p.Id
),
-- tag explode: one row per tag (null-safe parsing)
question_tags AS (
  SELECT q.Id AS QuestionId,
         lower(tag) AS Tag
  FROM Posts q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) AS tag
  ) t
  WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
),
-- tag popularity over last year (relative)
tag_popularity AS (
  SELECT qt.Tag,
         COUNT(*) AS QuestionCount,
         SUM(q.ViewCount) AS TotalViews,
         AVG(q.Score) AS AvgScore,
         ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS PopularityRank
  FROM question_tags qt
  JOIN Posts q ON q.Id = qt.QuestionId
  WHERE q.CreationDate >= now() - INTERVAL '365 days'
  GROUP BY qt.Tag
),
-- user aggregated stats including recency-weighted rep and penalized downvotes
user_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT b.Id) AS BadgeCount,
         SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgeWeight,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
         COALESCE( SUM(v.VoteTypeId = 2)::int, 0 ) AS UpVotesReceived,
         COALESCE( SUM(v.VoteTypeId = 3)::int, 0 ) AS DownVotesReceived,
         -- recency-weighted activity: recent actions count more
         (COALESCE( SUM( GREATEST(0, 1 - EXTRACT(EPOCH FROM (now() - COALESCE(p.LastActivityDate, u.LastAccessDate)))/(60*60*24*365)) ) ), 0) AS RecencyScoreHint
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON (p.OwnerUserId = u.Id OR p.LastEditorUserId = u.Id)
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- compute duplicate link clusters and centroids
linked_duplicates AS (
  SELECT pl.RelatedPostId AS CanonicalId,
         pl.PostId AS DuplicateId,
         COUNT(*) OVER (PARTITION BY pl.RelatedPostId) AS DupCount
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3 -- Duplicate
),
-- historical edit density per post
history_summary AS (
  SELECT ph.PostId,
         COUNT(*) AS Revisions,
         SUM(CASE WHEN ph.PostHistoryTypeId IN (5,2,8,24) THEN 1 ELSE 0 END) AS BodyEdits,
         MAX(ph.CreationDate) AS LastRevisionDate,
         MIN(ph.CreationDate) AS FirstRevisionDate,
         EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate)))/NULLIF(GREATEST(COUNT(*),1),0) AS AvgSecondsBetweenRevisions
  FROM PostHistory ph
  GROUP BY ph.PostId
),
-- assemble candidate questions with many metrics, include correlated subqueries
candidates AS (
  SELECT q.Id,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         q.FavoriteCount,
         q.Tags,
         ua.DisplayName AS OwnerName,
         ua.Reputation AS OwnerReputation,
         COALESCE(rs.LastActivity, q.LastActivityDate) AS ComputedLastActivity,
         hs.Revisions,
         hs.BodyEdits,
         COALESCE(lp.DupCount, 0) AS DuplicateCount,
         COALESCE(tp.PopularityRank, 999999) AS TopTagRank,
         -- correlated: average score of answers to this question
         (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
         -- correlated: time to accepted answer (if any) in hours
         (SELECT EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600
            FROM Posts a
           WHERE a.Id = q.AcceptedAnswerId
             AND q.AcceptedAnswerId IS NOT NULL
           LIMIT 1) AS HoursToAccepted,
         -- string manipulation: concise tag summary
         COALESCE(
           (SELECT string_agg(lower(t.tag), ',') 
            FROM (
              SELECT unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2),'><')) AS tag
            ) t
           ), '') AS NormalizedTags,
         -- complex expression combining many signals
         (q.Score * 1.5
          + COALESCE(q.ViewCount::numeric / NULLIF(GREATEST(q.AnswerCount,1),0), 0) * 0.25
          + COALESCE(q.FavoriteCount,0) * 2
          + COALESCE(hs.Revisions,0) * 0.5
          - COALESCE(lp.DupCount,0) * 1.2
          - CASE WHEN q.ClosedDate IS NOT NULL THEN 20 ELSE 0 END
         ) AS HeuristicEngagement
  FROM Posts q
  LEFT JOIN Users ua ON ua.Id = q.OwnerUserId
  LEFT JOIN recent_activity rs ON rs.PostId = q.Id
  LEFT JOIN history_summary hs ON hs.PostId = q.Id
  LEFT JOIN linked_duplicates lp ON lp.DuplicateId = q.Id
  LEFT JOIN LATERAL (
    SELECT MIN(tp.PopularityRank) AS PopularityRank
    FROM (
      SELECT unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2),'><')) AS tag
    ) t_tag
    LEFT JOIN tag_popularity tp ON tp.Tag = lower(t_tag.unnest)
  ) tp ON true
  WHERE q.PostTypeId = 1
),
-- rank candidates and get windowed aggregates
ranked AS (
  SELECT c.*,
         RANK() OVER (ORDER BY c.HeuristicEngagement DESC NULLS LAST) AS EngagementRank,
         ROW_NUMBER() OVER (PARTITION BY COALESCE(NULLIF(c.NormalizedTags,''), '<<untagged>>') ORDER BY c.HeuristicEngagement DESC) AS PerTagTopN,
         AVG(c.HeuristicEngagement) OVER () AS AvgHeuristic,
         PERCENT_RANK() OVER (ORDER BY COALESCE(c.HeuristicEngagement,0)) AS PercentileEngagement
  FROM candidates c
),
-- build a diagnostics set combining top engaged, most viewed, most revised using set operators
top_engaged AS (
  SELECT * FROM ranked WHERE EngagementRank <= 100
),
top_viewed AS (
  SELECT * FROM ranked WHERE ViewCount IS NOT NULL ORDER BY ViewCount DESC LIMIT 100
),
most_revised AS (
  SELECT * FROM ranked WHERE Revisions IS NOT NULL ORDER BY Revisions DESC LIMIT 100
),
diagnostics_union AS (
  SELECT * FROM top_engaged
  UNION
  SELECT * FROM top_viewed
  UNION
  SELECT * FROM most_revised
),
-- final enrichment: comments/votes distribution and edge-case flags
enriched AS (
  SELECT d.*,
         COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = d.Id), 0) AS CommentCountActual,
         COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) FROM Votes v WHERE v.PostId = d.Id), 0) AS VoteBalance,
         CASE
           WHEN d.HoursToAccepted IS NULL AND d.AnswerCount > 0 THEN 'HasAnswersNoAccepted'
           WHEN d.HoursToAccepted IS NULL AND d.AnswerCount = 0 THEN 'NoAnswers'
           WHEN d.HoursToAccepted IS NOT NULL AND d.HoursToAccepted <= 24 THEN 'AcceptedQuick'
           WHEN d.HoursToAccepted IS NOT NULL AND d.HoursToAccepted <= 168 THEN 'AcceptedWithinWeek'
           ELSE 'AcceptedLateOrNever'
         END AS AcceptanceTiming,
         -- Null logic/safety: text preview limited and sanitized
         COALESCE(NULLIF(substring(d.Title from 1 for 200),''), '[no title]') AS TitlePreview,
         -- text score: length of title * log(score+e)
         (char_length(COALESCE(d.Title,'')) * LN(GREATEST(COALESCE(d.Score,0),0) + EXP(1)))::numeric(18,6) AS TitleLengthScore
  FROM diagnostics_union d
)
SELECT
  e.Id,
  e.TitlePreview,
  e.NormalizedTags,
  e.OwnerName,
  e.OwnerReputation,
  e.Score,
  e.ViewCount,
  e.AnswerCount,
  e.CommentCountActual,
  e.FavoriteCount,
  e.Revisions,
  e.BodyEdits,
  e.DuplicateCount,
  e.HoursToAccepted,
  e.AcceptanceTiming,
  e.HeuristicEngagement,
  e.EngagementRank,
  e.PerTagTopN,
  e.PercentileEngagement,
  e.TitleLengthScore,
  CASE
    WHEN e.ViewCount >= (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'TopQuartileViews'
    WHEN e.ViewCount >= (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'MedianViews'
    ELSE 'LongTail'
  END AS ViewBucket,
  -- correlated subquery computing heterogeneity of answer scores (stddev)
  (SELECT COALESCE(STDDEV_POP(a.Score), 0) FROM Posts a WHERE a.ParentId = e.Id AND a.PostTypeId = 2) AS AnswerScoreStdDev,
  -- boolean-ish combined signal
  CASE WHEN e.HeuristicEngagement > e.AvgHeuristic THEN true ELSE false END AS AboveAverageEngagement
FROM enriched e
ORDER BY e.EngagementRank, e.ViewCount DESC
LIMIT 200;