-- {"query": "243.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4268} 
WITH
-- explode tags from question posts into rows
tag_explosion AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),

-- aggregate votes per post, broken down by common vote types and totals
votes_agg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOriginator,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId IN (5,8,9) THEN 1 ELSE 0 END) AS SpecialVotes,
    COUNT(*) AS TotalVotes,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),

-- aggregate comments per post
comments_agg AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountPerPost,
    MAX(c.CreationDate) AS LastCommentDate,
    SUM(CASE WHEN length(c.Text) > 200 THEN 1 ELSE 0 END) AS LongComments
  FROM Comments c
  GROUP BY c.PostId
),

-- rank answers per question and compute per-question answer stats
answers_ranked AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId AS AnswerOwner,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreation,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank,
    COUNT(*) OVER (PARTITION BY a.ParentId) AS AnswersPerQuestion,
    AVG(a.Score) OVER (PARTITION BY a.ParentId) AS AvgAnswerScoreForQuestion
  FROM Posts a
  WHERE a.PostTypeId = 2
),

-- per-user badge counts (by class) and last badge date
user_badges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),

-- user-level aggregates including correlated subqueries for top tag and top answer info
user_metrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(up.QCount,0) AS QuestionsAsked,
    COALESCE(ua.ACount,0) AS AnswersGiven,
    COALESCE(ROUND(CASE WHEN ua.ACount = 0 THEN 0.0 ELSE ua.TotalAnswerScore::numeric / NULLIF(ua.ACount,0) END,2),0) AS AvgAnswerScore,
    COALESCE(ub.BadgeCount,0) AS TotalBadges,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    -- correlated subquery: the user's highest scoring answer's top tag (if any)
    (
      SELECT te.Tag
      FROM tag_explosion te
      JOIN Posts p ON p.Id = te.PostId
      WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
      ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC
      LIMIT 1
    ) AS TopAnswerTag,
    -- correlated subquery: count of distinct tags the user has answered in
    (
      SELECT COUNT(DISTINCT te.Tag)
      FROM tag_explosion te
      JOIN Posts p ON p.Id = te.PostId
      WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
    ) AS DistinctTagsAnswered,
    -- correlated subquery: timestamp of user's highest scoring answer
    (
      SELECT p.CreationDate
      FROM Posts p
      WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
      ORDER BY p.Score DESC NULLS LAST
      LIMIT 1
    ) AS TopAnswerDate,
    -- a heuristic performance score combining reputation, badges and average answer score (handles NULLs)
    NULLIF(
      (
        COALESCE(u.Reputation,0) * 0.4
        + COALESCE(ub.GoldBadges,0) * 100
        + COALESCE(ub.SilverBadges,0) * 25
        + COALESCE(ub.BronzeBadges,0) * 5
        + (COALESCE(ROUND(CASE WHEN ua.ACount = 0 THEN 0.0 ELSE ua.TotalAnswerScore::numeric / NULLIF(ua.ACount,0) END,2),0) * 10)
      ), 0
    ) AS RawPerformanceComponent
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS QCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) up ON up.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS ACount, SUM(COALESCE(Score,0)) AS TotalAnswerScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
  ) ua ON ua.OwnerUserId = u.Id
  LEFT JOIN user_badges ub ON ub.UserId = u.Id
),

-- per-tag aggregated metrics, including last activity and avg scores
tag_metrics AS (
  SELECT
    te.Tag,
    COUNT(*) AS QuestionsWithTag,
    SUM(COALESCE(q.AnswerCount,0)) AS SumAnswerCount,
    ROUND(AVG(COALESCE(q.AnswerCount,0))::numeric,2) AS AvgAnswersPerQuestion,
    MAX(q.LastActivityDate) AS TagLastActivity,
    SUM(COALESCE(vs.UpVotes,0)) AS TagUpVotes,
    SUM(COALESCE(vs.DownVotes,0)) AS TagDownVotes,
    SUM(COALESCE(ca.CommentCountPerPost,0)) AS TagComments,
    -- tag popularity ratio with null-safe logic
    CASE WHEN COUNT(*) = 0 THEN 0 ELSE ROUND((SUM(COALESCE(vs.UpVotes,0))::numeric / NULLIF(COUNT(*),0)) ,2) END AS UpVotesPerQuestion
  FROM tag_explosion te
  LEFT JOIN Posts q ON q.Id = te.PostId
  LEFT JOIN votes_agg vs ON vs.PostId = q.Id
  LEFT JOIN comments_agg ca ON ca.PostId = q.Id
  GROUP BY te.Tag
),

-- label tags as active vs dormant using set operator (UNION ALL)
tag_activity AS (
  SELECT tm.Tag, 'active' AS Status, tm.QuestionsWithTag, tm.AvgAnswersPerQuestion, tm.TagLastActivity
  FROM tag_metrics tm
  WHERE tm.TagLastActivity > now() - interval '180 days'
  UNION ALL
  SELECT tm.Tag, 'dormant' AS Status, tm.QuestionsWithTag, tm.AvgAnswersPerQuestion, tm.TagLastActivity
  FROM tag_metrics tm
  WHERE tm.TagLastActivity <= now() - interval '180 days' OR tm.TagLastActivity IS NULL
),

-- compute per-question enriched info (joins answers, votes, comments)
question_enriched AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate AS QuestionCreation,
    q.AnswerCount,
    COALESCE(va.UpVotes,0) AS QuestionUpVotes,
    COALESCE(va.DownVotes,0) AS QuestionDownVotes,
    COALESCE(ca.CommentCountPerPost,0) AS QuestionComments,
    -- fastest accepted answer delta (correlated)
    (
      SELECT EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))::bigint
      FROM Posts a
      WHERE a.ParentId = q.Id AND a.Id = q.AcceptedAnswerId
      LIMIT 1
    ) AS AcceptedAnswerSeconds,
    -- median answer score using window functions
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(a.Score,0)) OVER (PARTITION BY q.Id) AS MedianAnswerScore
  FROM Posts q
  LEFT JOIN votes_agg va ON va.PostId = q.Id
  LEFT JOIN comments_agg ca ON ca.PostId = q.Id
  LEFT JOIN Posts a ON a.ParentId = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.AnswerCount, va.UpVotes, va.DownVotes, ca.CommentCountPerPost, q.AcceptedAnswerId
)

-- final result: combine users with their top tag metrics and recent questions they touched; heavy use of outer joins, windowing, NULL logic and expressions
SELECT
  um.UserId,
  um.DisplayName,
  um.Reputation,
  um.QuestionsAsked,
  um.AnswersGiven,
  um.AvgAnswerScore,
  COALESCE(um.TopAnswerTag, '(none)') AS TopAnswerTag,
  COALESCE(tm.QuestionsWithTag,0) AS TopTagQuestionCount,
  COALESCE(tm.UpVotesPerQuestion,0) AS TopTagUpVotesPerQuestion,
  ta.Status AS TopTagStatus,
  um.DistinctTagsAnswered,
  COALESCE(um.RawPerformanceComponent, 0) AS RawPerformanceComponent,
  -- normalized score across returned dataset using window functions
  ROUND( (COALESCE(um.RawPerformanceComponent,0) - MIN(COALESCE(um.RawPerformanceComponent,0)) OVER ())::numeric
         / NULLIF( (MAX(COALESCE(um.RawPerformanceComponent,0)) OVER () - MIN(COALESCE(um.RawPerformanceComponent,0)) OVER ()), 0)
         * 100, 2) AS NormalizedPerformancePct,
  -- recent questions the user asked (if any), concatenated as a string; demonstrates string aggregation and NULL handling
  COALESCE(
    (SELECT string_agg(
        '[' || q.QuestionId::text || ']' || left(coalesce(q.Title,''),120)
        || ' (A:' || COALESCE(q.AnswerCount::text,'0') || ',U:' || COALESCE(q.QuestionUpVotes::text,'0') || ')'
      , ' || ')
     FROM question_enriched q
     WHERE q.OwnerUserId = um.UserId
     ORDER BY q.QuestionCreation DESC
     LIMIT 5
    ),
    '(no recent questions)'
  ) AS RecentQuestionsSummary,
  -- heavy predicate: whether user is a "top contributor" on their top tag, using correlated subquery with NULL logic
  CASE
    WHEN um.TopAnswerTag IS NULL THEN 'no-top-tag'
    WHEN EXISTS (
      SELECT 1
      FROM tag_explosion te
      JOIN Posts p ON p.Id = te.PostId
      WHERE te.Tag = um.TopAnswerTag
        AND p.PostTypeId = 2
        AND p.OwnerUserId = um.UserId
        AND p.Score >= (
          SELECT COALESCE(MAX(p2.Score),0)
          FROM Posts p2
          JOIN tag_explosion te2 ON te2.PostId = p2.Id
          WHERE te2.Tag = um.TopAnswerTag AND p2.PostTypeId = 2
        ) - 5 -- within 5 points of top answer for that tag
      LIMIT 1
    ) THEN 'top-contributor'
    ELSE 'participant'
  END AS ContributionRole,
  -- ranking among users by normalized performance
  DENSE_RANK() OVER (ORDER BY COALESCE(um.RawPerformanceComponent,0) DESC) AS PerformanceRank
FROM user_metrics um
LEFT JOIN tag_metrics tm ON tm.Tag = um.TopAnswerTag
LEFT JOIN tag_activity ta ON ta.Tag = um.TopAnswerTag AND ta.Status = 'active'
-- include all users even if they have no tags (outer join effect already), and filter to users who have any activity (questions or answers) or a reputation above a threshold
WHERE (um.QuestionsAsked > 0 OR um.AnswersGiven > 0 OR um.Reputation > 100)
ORDER BY PerformanceRank ASC, NormalizedPerformancePct DESC
;