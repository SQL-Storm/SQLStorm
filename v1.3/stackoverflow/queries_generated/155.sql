-- {"query": "155.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2983} 
WITH
-- basic aggregates per user from Posts and Comments
post_agg AS (
  SELECT
    u.Id AS UserId,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    SUM(COALESCE(p.Score,0)) AS TotalPostScore,
    AVG(NULLIF(p.Score,0)) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
-- badges aggregated, with latest badge per user using window functions
badges_ranked AS (
  SELECT
    b.*,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC, b.Id DESC) AS rn,
    COUNT(*) OVER (PARTITION BY b.UserId) AS BadgeCount
  FROM Badges b
),
badge_summary AS (
  SELECT
    UserId,
    BadgeCount,
    MAX(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS HasGold,
    MAX(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS HasSilver,
    MAX(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS HasBronze,
    MAX(Date) FILTER (WHERE rn = 1) AS MostRecentBadgeDate,
    MAX(Name) FILTER (WHERE rn = 1) AS MostRecentBadgeName
  FROM badges_ranked
  GROUP BY UserId, BadgeCount
),
-- votes given and received
vote_summary AS (
  SELECT
    u.Id AS UserId,
    SUM(CASE WHEN v.UserId = u.Id AND v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.UserId = u.Id AND v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    SUM(CASE WHEN p.OwnerUserId = u.Id AND v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN p.OwnerUserId = u.Id AND v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
  FROM Users u
  LEFT JOIN Votes v ON (v.UserId = u.Id OR v.PostId IS NOT NULL)
  LEFT JOIN Posts p ON p.Id = v.PostId
  GROUP BY u.Id
),
-- tag usage: parse Tags field on questions and explode tags
question_tags AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_usage AS (
  SELECT
    qt.OwnerUserId AS UserId,
    qt.Tag,
    COUNT(*) AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY qt.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
  FROM question_tags qt
  GROUP BY qt.OwnerUserId, qt.Tag
),
-- top tag per user (if any)
top_tag AS (
  SELECT UserId, Tag AS TopTag, TagCount AS TopTagCount
  FROM tag_usage
  WHERE TagRank = 1
),
-- recent mixed activity timeline (posts, comments, votes) per user using UNION ALL and window functions
mixed_activity AS (
  SELECT
    u.Id AS UserId,
    'post'::text AS ActivityType,
    p.Id AS ItemId,
    p.CreationDate AS ActivityDate,
    COALESCE(p.Score,0) AS Impact,
    p.Title AS Title,
    p.Body IS NOT NULL AS HasBody
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id

  UNION ALL

  SELECT
    u.Id AS UserId,
    'comment'::text,
    c.Id,
    c.CreationDate,
    COALESCE(c.Score,0),
    LEFT(c.Text,200),
    FALSE
  FROM Users u
  LEFT JOIN Comments c ON c.UserId = u.Id

  UNION ALL

  SELECT
    u.Id AS UserId,
    'vote'::text,
    v.Id,
    v.CreationDate,
    COALESCE(v.BountyAmount,0),
    vt.Name,
    FALSE
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
),
activity_ranked AS (
  SELECT
    ma.*,
    ROW_NUMBER() OVER (PARTITION BY ma.UserId ORDER BY ma.ActivityDate DESC NULLS LAST) AS Rn,
    COUNT(*) OVER (PARTITION BY ma.UserId) AS ActivityCount
  FROM mixed_activity ma
),
recent_activity AS (
  SELECT UserId,
         MAX(ActivityDate) FILTER (WHERE Rn = 1) AS MostRecentActivity,
         ActivityCount,
         MAX(ActivityType) FILTER (WHERE Rn = 1) AS MostRecentActivityType,
         MAX(ItemId) FILTER (WHERE Rn = 1) AS MostRecentItemId
  FROM activity_ranked
  GROUP BY UserId, ActivityCount
),
-- example of correlated subqueries and EXISTS to detect special conditions
special_flags AS (
  SELECT
    u.Id AS UserId,
    CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score >= 100) THEN 1 ELSE 0 END AS HasHighScoringPost,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswersProvided,
    (SELECT COUNT(DISTINCT pt.PostTypeId) FROM Posts pt WHERE pt.OwnerUserId = u.Id) AS DistinctPostTypes
  FROM Users u
),
-- compute a synthetic "influence" metric mixing reputation, badge count, votes received and tag breadth
influence AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COALESCE(b.BadgeCount,0) AS BadgeCount,
    COALESCE(vs.UpVotesReceived,0) - COALESCE(vs.DownVotesReceived,0) AS NetVotesReceived,
    COALESCE(tt.TopTagCount,0) AS TopTagCount,
    -- a deliberately complicated expression to stress calc engine
    (LOG(GREATEST(1, u.Reputation)) * (1 + COALESCE(b.BadgeCount,0)/10.0) + COALESCE(vs.UpVotesReceived,0) * 0.5
      - COALESCE(vs.DownVotesReceived,0) * 0.75
      + sqrt(GREATEST(0, COALESCE(tt.TopTagCount,0))) * 2
      + CASE WHEN u.Views > 10000 THEN 5 ELSE 0 END
      + CASE WHEN u.CreationDate < now() - INTERVAL '5 years' THEN 2 ELSE 0 END
    )::numeric(20,6) AS InfluenceScore
  FROM Users u
  LEFT JOIN badge_summary b ON b.UserId = u.Id
  LEFT JOIN vote_summary vs ON vs.UserId = u.Id
  LEFT JOIN top_tag tt ON tt.UserId = u.Id
),
-- pick top 250 users by influence for expensive correlated monitoring
top_influencers AS (
  SELECT *
  FROM influence
  ORDER BY InfluenceScore DESC NULLS LAST
  LIMIT 250
),
-- example of set operator usage: users who have asked questions but never answered vs vice versa
askers AS (
  SELECT OwnerUserId AS UserId FROM Posts WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
  EXCEPT
  SELECT OwnerUserId FROM Posts WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
),
answerers AS (
  SELECT OwnerUserId AS UserId FROM Posts WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
  EXCEPT
  SELECT OwnerUserId FROM Posts WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
)
-- final selection: assemble all info, include correlated scalar subquery, left joins, and complicated predicates
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  COALESCE(pa.Questions,0) AS QuestionCount,
  COALESCE(pa.Answers,0) AS AnswerCount,
  COALESCE(pa.TotalPostScore,0) AS TotalPostScore,
  COALESCE(bs.BadgeCount,0) AS BadgeCount,
  COALESCE(vs.UpVotesGiven,0) AS UpVotesGiven,
  COALESCE(vs.UpVotesReceived,0) AS UpVotesReceived,
  COALESCE(ts.TopTag,'<none>') AS TopTag,
  COALESCE(ts.TopTagCount,0) AS TopTagCount,
  COALESCE(ra.MostRecentActivity, u.LastAccessDate) AS LastActivity,
  COALESCE(sf.HasHighScoringPost,0) AS HasHighScoringPost,
  COALESCE(sf.AcceptedAnswersProvided,0) AS AcceptedAnswersProvided,
  COALESCE(inf.InfluenceScore,0) AS InfluenceScore,
  -- correlated scalar subquery: count of distinct tags used by user across their questions (NULL-safe)
  (SELECT COUNT(DISTINCT tag)
   FROM (
     SELECT unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS tag
     FROM Posts p
     WHERE p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.Tags IS NOT NULL
   ) t
  ) AS DistinctTagsUsed,
  -- an illustrative complex predicate: "veteran" if created long ago and has reasonable activity, else 'new'
  CASE
    WHEN u.CreationDate < now() - INTERVAL '3 years' AND COALESCE(pa.Answers,0) + COALESCE(pa.Questions,0) >= 10 THEN 'veteran'
    WHEN u.CreationDate < now() - INTERVAL '1 year' AND COALESCE(pa.Answers,0) + COALESCE(pa.Questions,0) BETWEEN 3 AND 9 THEN 'established'
    WHEN COALESCE(pa.Answers,0) + COALESCE(pa.Questions,0) = 0 THEN 'lurker'
    ELSE 'new'
  END AS Status,
  -- string composition and NULL logic to produce a summary snippet
  LEFT(
    COALESCE(u.DisplayName,'[anonymous]') || ' | rep:' || COALESCE(u.Reputation::text,'0')
    || ' | badges:' || COALESCE(CAST(COALESCE(bs.BadgeCount,0) AS text),'0')
    || ' | top-tag:' || COALESCE(ts.TopTag,'none')
    , 120) AS SummarySnippet,
  -- flags from set operators
  CASE WHEN u.Id IN (SELECT UserId FROM askers) THEN 1 ELSE 0 END AS AskerOnly,
  CASE WHEN u.Id IN (SELECT UserId FROM answerers) THEN 1 ELSE 0 END AS AnswererOnly,
  -- last: a correlated existence check for recent high-impact activity (answers with score >=50 in last year)
  CASE WHEN EXISTS (
    SELECT 1 FROM Posts p2
    WHERE p2.OwnerUserId = u.Id
      AND p2.PostTypeId = 2
      AND p2.Score >= 50
      AND p2.CreationDate >= now() - INTERVAL '1 year'
  ) THEN 1 ELSE 0 END AS RecentHighImpactAnswer
FROM Users u
LEFT JOIN post_agg pa ON pa.UserId = u.Id
LEFT JOIN badge_summary bs ON bs.UserId = u.Id
LEFT JOIN vote_summary vs ON vs.UserId = u.Id
LEFT JOIN top_tag ts ON ts.UserId = u.Id
LEFT JOIN recent_activity ra ON ra.UserId = u.Id
LEFT JOIN special_flags sf ON sf.UserId = u.Id
LEFT JOIN influence inf ON inf.UserId = u.Id
WHERE
  -- deliberately complicated WHERE: include active or influential users, or those with a top tag, or admins (AccountId IS NOT NULL)
  (
    (COALESCE(pa.Questions,0) + COALESCE(pa.Answers,0) > 0 AND COALESCE(ra.MostRecentActivity, u.LastAccessDate) >= now() - INTERVAL '2 years')
    OR COALESCE(inf.InfluenceScore,0) > 10
    OR ts.TopTag IS NOT NULL
    OR u.AccountId IS NOT NULL
  )
ORDER BY InfluenceScore DESC NULLS LAST, TotalPostScore DESC NULLS LAST, LastActivity DESC NULLS LAST
LIMIT 200;