-- {"query": "44.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2345} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerName,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    -- normalized tag list (split and trim)
    regexp_split_to_table(coalesce(substring(p.Tags from 2 for char_length(p.Tags)-2), ''), '><') AS Tag
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= now() - interval '2 years'
    AND p.PostTypeId IN (1,2) -- questions and answers
),
answer_stats AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(*) FILTER (WHERE a.Score > 0) AS PositiveAnswers,
    COUNT(*) FILTER (WHERE a.Score <= 0) AS NonPositiveAnswers,
    AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
    MAX(a.Score) AS MaxAnswerScore,
    MIN(a.CreationDate) AS FirstAnswerAt,
    MAX(a.CreationDate) AS LastAnswerAt,
    COUNT(*) AS TotalAnswers
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
user_engagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
    COUNT(b.Id) AS BadgesEarned,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
popular_tags AS (
  SELECT
    Tag,
    COUNT(DISTINCT PostId) AS QuestionsWithTag,
    SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM recent_activity
  GROUP BY Tag
  HAVING COUNT(DISTINCT PostId) > 50
),
complex_joins AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate AS QuestionCreated,
    q.Score AS QuestionScore,
    ae.PositiveAnswers,
    ae.NonPositiveAnswers,
    ae.AvgAnswerScore,
    ae.TotalAnswers,
    r.Tag AS PrimaryTag,
    pt.Name AS PostTypeName,
    -- last editor info with NULL logic and correlated subquery
    COALESCE(
      (SELECT u2.DisplayName FROM Users u2 WHERE u2.Id = q.LastEditorUserId),
      q.LastEditorDisplayName,
      '(unknown)'
    ) AS LastEditorName,
    -- existence checks with set operators
    CASE WHEN EXISTS (SELECT 1 FROM Votes vx WHERE vx.PostId = q.Id AND vx.VoteTypeId = 2) THEN true ELSE false END AS HasUpvotes,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN true ELSE false END AS HasAccepted,
    -- computed popularity metric mixing views, score, and recency
    (COALESCE(q.ViewCount,0) * 0.2 + COALESCE(q.Score,0) * 15 + COALESCE(ae.AvgAnswerScore,0) * 10) /
      (GREATEST(1, EXTRACT(EPOCH FROM now() - q.CreationDate)/86400) ^ 0.5) AS PopularityScore
  FROM Posts q
  LEFT JOIN recent_activity r ON r.PostId = q.Id AND r.PostTypeId = 1
  LEFT JOIN answer_stats ae ON ae.QuestionId = q.Id
  LEFT JOIN PostTypes pt ON pt.Id = q.PostTypeId
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - interval '2 years'
),
ranked_questions AS (
  SELECT
    cj.*,
    ROW_NUMBER() OVER (PARTITION BY cj.PrimaryTag ORDER BY cj.PopularityScore DESC NULLS LAST) AS TagRank,
    RANK() OVER (ORDER BY cj.PopularityScore DESC NULLS LAST) AS GlobalRank,
    NTILE(10) OVER (ORDER BY cj.PopularityScore DESC NULLS LAST) AS PopularityDecile
  FROM complex_joins cj
  WHERE cj.PrimaryTag IS NOT NULL
),
tag_leaders AS (
  SELECT
    rt.PrimaryTag,
    COUNT(*) FILTER (WHERE rt.TagRank = 1) AS LeaderCount,
    AVG(rt.PopularityScore) AS AvgTagPopularity,
    MAX(rt.PopularityScore) AS MaxTagPopularity
  FROM ranked_questions rt
  GROUP BY rt.PrimaryTag
),
duplicates_and_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    p1.Score AS PostScore,
    p2.Score AS RelatedScore,
    -- detect reciprocal links using self-join
    CASE WHEN EXISTS (
      SELECT 1 FROM PostLinks pl2 WHERE pl2.PostId = pl.RelatedPostId AND pl2.RelatedPostId = pl.PostId
    ) THEN true ELSE false END AS IsReciprocal
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Posts p1 ON p1.Id = pl.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE pl.CreationDate >= now() - interval '1 year'
),
heavy_compute AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.PrimaryTag,
    q.OwnerUserId,
    q.OwnerName,
    q.PopularityScore,
    q.TagRank,
    q.GlobalRank,
    q.PopularityDecile,
    tl.LeaderCount,
    tl.AvgTagPopularity,
    tl.MaxTagPopularity,
    ue.QuestionsPosted,
    ue.AnswersPosted,
    ue.Reputation,
    ue.BadgesEarned,
    -- complex string expression mixing NULLs and conditional formatting
    CASE
      WHEN ue.Reputation IS NULL THEN 'user:unknown'
      WHEN ue.Reputation < 100 THEN 'newbie:' || coalesce(ue.DisplayName, 'anon')
      WHEN ue.Reputation BETWEEN 100 AND 1000 THEN 'active:' || coalesce(ue.DisplayName, 'anon')
      ELSE 'veteran:' || coalesce(ue.DisplayName, 'anon')
    END AS UserBucket,
    -- correlated scalar subquery retrieving top comment on question if any
    (SELECT c.Text
     FROM Comments c
     WHERE c.PostId = q.QuestionId
     ORDER BY c.Score DESC NULLS LAST, c.CreationDate ASC
     LIMIT 1) AS TopComment,
    -- compute an estimated engagement metric with NULL-safe arithmetic and CASE
    CASE
      WHEN q.TotalAnswers IS NULL THEN 0
      WHEN q.TotalAnswers = 0 THEN LEAST(1, q.PopularityScore/100.0)
      ELSE (q.PopularityScore * (1 + GREATEST(0, q.TotalAnswers - 1) * 0.05))
    END AS EngagementEstimate
  FROM ranked_questions q
  LEFT JOIN tag_leaders tl ON tl.PrimaryTag = q.PrimaryTag
  LEFT JOIN Users ue ON ue.Id = q.OwnerUserId
  WHERE q.GlobalRank <= 5000
)
-- final selection combining windowed aggregates, set operator for a small union, and complex predicates
SELECT
  hc.QuestionId,
  hc.Title,
  hc.PrimaryTag,
  hc.OwnerUserId,
  hc.UserBucket,
  hc.Reputation,
  hc.QuestionsPosted,
  hc.AnswersPosted,
  ROUND(hc.PopularityScore::numeric,3) AS PopularityScore,
  hc.TagRank,
  hc.GlobalRank,
  hc.PopularityDecile,
  hc.LeaderCount,
  ROUND(hc.AvgTagPopularity::numeric,3) AS AvgTagPopularity,
  hc.TopComment,
  hc.EngagementEstimate
FROM heavy_compute hc
WHERE
  -- complicated predicate mixing NULL checks, regex, and boolean logic
  (
    hc.PrimaryTag ~* '^(sql|postgres|performance|benchmark)' OR
    hc.Title ILIKE '%performance%' OR
    hc.UserBucket LIKE 'veteran:%'
  )
  AND (hc.EngagementEstimate > 2 OR hc.PopularityDecile <= 3)
UNION
-- include a few low-activity but interesting edge cases using INTERSECT/EXCEPT style logic
SELECT
  e.QuestionId,
  e.Title,
  e.PrimaryTag,
  e.OwnerUserId,
  e.UserBucket,
  e.Reputation,
  e.QuestionsPosted,
  e.AnswersPosted,
  ROUND(e.PopularityScore::numeric,3) AS PopularityScore,
  e.TagRank,
  e.GlobalRank,
  e.PopularityDecile,
  e.LeaderCount,
  ROUND(e.AvgTagPopularity::numeric,3) AS AvgTagPopularity,
  e.TopComment,
  e.EngagementEstimate
FROM heavy_compute e
WHERE e.EngagementEstimate < 0.5
  AND (e.Reputation IS NULL OR e.Reputation < 10)
  AND e.PrimaryTag IS NOT NULL
EXCEPT
SELECT
  hc2.QuestionId,
  hc2.Title,
  hc2.PrimaryTag,
  hc2.OwnerUserId,
  hc2.UserBucket,
  hc2.Reputation,
  hc2.QuestionsPosted,
  hc2.AnswersPosted,
  ROUND(hc2.PopularityScore::numeric,3) AS PopularityScore,
  hc2.TagRank,
  hc2.GlobalRank,
  hc2.PopularityDecile,
  hc2.LeaderCount,
  ROUND(hc2.AvgTagPopularity::numeric,3) AS AvgTagPopularity,
  hc2.TopComment,
  hc2.EngagementEstimate
FROM heavy_compute hc2
WHERE hc2.PrimaryTag = 'deprecated'
ORDER BY PopularityScore DESC NULLS LAST, GlobalRank ASC
LIMIT 200;