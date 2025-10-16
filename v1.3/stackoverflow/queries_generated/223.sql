-- {"query": "223.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4111} 
WITH
-- Basic user metrics and age
user_basics AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    now() AT TIME ZONE 'UTC' - u.CreationDate AS AccountAge,
    COALESCE(u.Location,'') AS Location,
    COALESCE(u.ProfileImageUrl,'') AS Avatar,
    CASE WHEN u.EmailHash IS NOT NULL AND u.EmailHash <> '' THEN 'gravatar://' || u.EmailHash ELSE NULL END AS AvatarHash
  FROM Users u
),

-- Aggregate posts by user (questions / answers / totals and score/view statistics)
posts_by_user AS (
  SELECT
    COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
    COUNT(*) AS TotalPosts,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS TotalScore,
    AVG(NULLIF(p.Score,0)) FILTER (WHERE p.PostTypeId = 1) AS AvgScoreQuestion,
    AVG(NULLIF(p.Score,0)) FILTER (WHERE p.PostTypeId = 2) AS AvgScoreAnswer,
    MAX(p.CreationDate) AS LastPostDate,
    MIN(p.CreationDate) AS FirstPostDate,
    SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
  GROUP BY COALESCE(p.OwnerUserId, -1)
),

-- Expand tags (questions only) into one row per tag
tag_expansion AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''), 2, GREATEST(char_length(coalesce(p.Tags,'')) - 2,0)), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND coalesce(p.Tags,'') <> ''
),

-- Per-user tag statistics
tag_stats AS (
  SELECT
    te.OwnerUserId,
    te.tag AS TagName,
    COUNT(*) AS QuestionsWithTag,
    AVG(p.ViewCount) AS AvgTagQuestionViews,
    SUM(p.Score) AS TotalTagScore
  FROM tag_expansion te
  JOIN Posts p ON p.Id = te.PostId
  WHERE te.OwnerUserId IS NOT NULL AND te.OwnerUserId > 0
  GROUP BY te.OwnerUserId, te.tag
),

-- Each user's top tag (by question count and score as tie-break)
top_tag_per_user AS (
  SELECT OwnerUserId, TagName, QuestionsWithTag, AvgTagQuestionViews, TotalTagScore
  FROM (
    SELECT
      ts.*,
      ROW_NUMBER() OVER (PARTITION BY ts.OwnerUserId ORDER BY ts.QuestionsWithTag DESC, ts.TotalTagScore DESC, ts.TagName) AS rn
    FROM tag_stats ts
  ) x
  WHERE rn = 1
),

-- Badges summary per user
badges_summary AS (
  SELECT
    b.UserId,
    COUNT(*) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
  FROM Badges b
  GROUP BY b.UserId
),

-- Votes attributed to post owners (counts of vote types per user)
votes_attributed AS (
  SELECT
    COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 1) AS AcceptedReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoritedReceived,
    SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 WHEN v.VoteTypeId IN (3) THEN -1 ELSE 0 END) AS NetVoteImpact
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
  GROUP BY COALESCE(p.OwnerUserId, -1)
),

-- Commenter reach: distinct commenters across a user's posts
commenters_summary AS (
  SELECT
    p.OwnerUserId,
    COUNT(DISTINCT c.UserId) AS DistinctCommenters,
    COUNT(c.Id) AS TotalComments
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
  GROUP BY p.OwnerUserId
),

-- Links to and from a user's posts (duplicates / linked posts)
links_summary AS (
  SELECT
    p.OwnerUserId,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedOutCount,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinkCount
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
  GROUP BY p.OwnerUserId
),

-- Post history metrics: edits, closes, community bumps
history_summary AS (
  SELECT
    ph.UserId,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,4,24)) AS EditsMade,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS ClosesReopens,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 50) AS CommunityBumps
  FROM PostHistory ph
  GROUP BY ph.UserId
),

-- Users who have badges but no posts (set operator example)
badged_but_no_posts AS (
  SELECT DISTINCT UserId FROM Badges
  EXCEPT
  SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL
),

-- A derived set of "top contributors" using simple thresholds (UNION)
top_contributors AS (
  SELECT OwnerUserId AS UserId FROM posts_by_user WHERE AnswerCount >= 20
  UNION
  SELECT OwnerUserId AS UserId FROM posts_by_user WHERE QuestionCount >= 10
),

-- Compose a per-user summary combining lots of metrics and computed scores
user_summary AS (
  SELECT
    ub.Id AS UserId,
    ub.DisplayName,
    ub.Reputation,
    pb.TotalPosts,
    pb.QuestionCount,
    pb.AnswerCount,
    COALESCE(pb.TotalScore,0) AS TotalPostScore,
    COALESCE(vs.UpVotesReceived,0) AS UpVotesReceived,
    COALESCE(vs.DownVotesReceived,0) AS DownVotesReceived,
    COALESCE(vs.AcceptedReceived,0) AS AcceptedReceived,
    COALESCE(bs.TotalBadges,0) AS TotalBadges,
    COALESCE(bs.GoldBadges,0) AS GoldBadges,
    COALESCE(cs.DistinctCommenters,0) AS DistinctCommenters,
    COALESCE(ls.LinkedOutCount,0) AS LinkedOutCount,
    COALESCE(hs.EditsMade,0) AS EditsMade,
    COALESCE(tt.TagName,'(none)') AS TopTag,
    COALESCE(tt.QuestionsWithTag,0) AS TopTagCount,
    CASE WHEN tc.UserId IS NOT NULL THEN true ELSE false END AS IsTopContributor,
    -- composite influence score (arbitrary weighted formula to stress calculations)
    (
      COALESCE(pb.TotalScore,0) * 1.5
      + COALESCE(vs.UpVotesReceived,0) * 2.0
      - COALESCE(vs.DownVotesReceived,0) * 1.25
      + COALESCE(bs.GoldBadges,0) * 50
      + COALESCE(bs.SilverBadges,0) * 15
      + COALESCE(bs.BronzeBadges,0) * 5
      + COALESCE(cs.DistinctCommenters,0) * 3
      + COALESCE(pb.QuestionCount,0) * 2
      + COALESCE(pb.AnswerCount,0) * 2.5
      + COALESCE(tt.QuestionsWithTag,0) * 1.2
      - GREATEST(0, COALESCE(vs.DownVotesReceived,0) - COALESCE(vs.UpVotesReceived,0)) * 2
    ) AS InfluenceScore,
    ub.AccountAge,
    -- a textual compact summary combining multiple fields
    concat_ws(' | ',
      'rep:'||ub.Reputation,
      'posts:'||COALESCE(pb.TotalPosts,0),
      'q:'||COALESCE(pb.QuestionCount,0),
      'a:'||COALESCE(pb.AnswerCount,0),
      'top:'||COALESCE(tt.TagName,'(none)')
    ) AS CompactSummary
  FROM user_basics ub
  LEFT JOIN posts_by_user pb ON pb.OwnerUserId = ub.Id
  LEFT JOIN votes_attributed vs ON vs.OwnerUserId = ub.Id
  LEFT JOIN badges_summary bs ON bs.UserId = ub.Id
  LEFT JOIN commenters_summary cs ON cs.OwnerUserId = ub.Id
  LEFT JOIN links_summary ls ON ls.OwnerUserId = ub.Id
  LEFT JOIN history_summary hs ON hs.UserId = ub.Id
  LEFT JOIN top_tag_per_user tt ON tt.OwnerUserId = ub.Id
  LEFT JOIN top_contributors tc ON tc.UserId = ub.Id
),

-- Compute windowed ranks and rolling aggregates for the top N by influence
ranked_users AS (
  SELECT
    us.*,
    RANK() OVER (ORDER BY us.InfluenceScore DESC NULLS LAST) AS InfluenceRank,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC NULLS LAST) AS ReputationRank,
    PERCENT_RANK() OVER (ORDER BY us.InfluenceScore) AS InfluencePercentile,
    AVG(us.InfluenceScore) OVER () AS AvgInfluence,
    STDDEV_POP(us.InfluenceScore) OVER () AS StdDevInfluence
  FROM user_summary us
)

-- Final selection: top 200 users by composite influence, with correlated subqueries and NULL logic
SELECT
  ru.UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.InfluenceScore,
  ru.InfluenceRank,
  ru.ReputationRank,
  ru.InfluencePercentile,
  ru.TotalPosts,
  ru.QuestionCount,
  ru.AnswerCount,
  ru.TopTag,
  ru.TopTagCount,
  ru.TotalBadges,
  ru.GoldBadges,
  ru.DistinctCommenters,
  ru.EditsMade,
  ru.LinkedOutCount,
  ru.CompactSummary,
  -- correlated subquery: the user's single most-viewed question title (if any)
  (
    SELECT p.Title
    FROM Posts p
    WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1 AND p.Title IS NOT NULL
    ORDER BY COALESCE(p.ViewCount,0) DESC NULLS LAST, COALESCE(p.Score,0) DESC
    LIMIT 1
  ) AS MostViewedQuestionTitle,
  -- correlated subquery: median answer score for this user's answers (approx via percentile_cont)
  (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(p.Score,0))
    FROM Posts p
    WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 2
  )::numeric(10,2) AS MedianAnswerScore,
  -- compute recency metric (days since last post)
  GREATEST(0, (EXTRACT(EPOCH FROM (now() AT TIME ZONE 'UTC' - COALESCE(
    (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = ru.UserId), ru.AccountAge
  ))) / 86400))::int AS DaysSinceLastPost,
  -- boolean flags and null-aware labels
  CASE WHEN ru.IsTopContributor THEN 'top' ELSE 'regular' END AS ContributorCategory,
  CASE WHEN ru.TotalBadges > 0 THEN 'has_badges' ELSE 'no_badges' END AS BadgeStatus,
  -- an integrity check: users who have badges but no posts flagged via the CTE
  CASE WHEN ru.UserId IN (SELECT UserId FROM badged_but_no_posts) THEN true ELSE false END AS BadgedButNoPosts
FROM ranked_users ru
WHERE ru.InfluenceScore IS NOT NULL
ORDER BY ru.InfluenceScore DESC NULLS LAST, ru.Reputation DESC
LIMIT 200;