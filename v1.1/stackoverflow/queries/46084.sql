WITH RECURSIVE UserInfluence AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) as QuestionCount,
    COUNT(DISTINCT a.Id) as AnswerCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN a.PostTypeId = 2 THEN a.Score ELSE 0 END), 0) as TotalAnswerScore
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
  LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
  WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT a.Id) > 5
),
TagExpertise AS (
  SELECT 
    p.OwnerUserId,
    TRIM(tag) AS TagName,
    COUNT(*) as TagUsageCount,
    AVG(p.Score) as AvgTagScore,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as AcceptedQuestions
  FROM Posts p,
  LATERAL (
    SELECT regexp_split_to_table(
      substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)),
      '><'
    ) AS tag
  ) s
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL 
    AND p.CreationDate >= TIMESTAMP '2020-01-01'
  GROUP BY p.OwnerUserId, TRIM(tag)
),
AnswerAcceptanceRate AS (
  SELECT 
    a.OwnerUserId,
    COUNT(*) as TotalAnswers,
    SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) as AcceptedAnswers,
    AVG(a.Score) as AvgAnswerScore,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) as MedianAnswerScore
  FROM Posts a
  JOIN Posts q ON a.ParentId = q.Id
  WHERE a.PostTypeId = 2 
    AND a.CreationDate >= TIMESTAMP '2020-01-01'
  GROUP BY a.OwnerUserId
  HAVING COUNT(*) >= 3
),
VotingBehavior AS (
  SELECT 
    v.UserId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpvotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownvotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as FavoritesGiven,
    COUNT(DISTINCT v.PostId) as UniquePostsVoted
  FROM Votes v
  WHERE v.CreationDate >= TIMESTAMP '2020-01-01'
  GROUP BY v.UserId
),
CommentActivity AS (
  SELECT 
    c.UserId,
    COUNT(*) as CommentCount,
    AVG(c.Score) as AvgCommentScore,
    COUNT(DISTINCT c.PostId) as UniquePostsCommented
  FROM Comments c
  WHERE c.CreationDate >= TIMESTAMP '2020-01-01' AND c.UserId IS NOT NULL
  GROUP BY c.UserId
),
BadgeAchievements AS (
  SELECT 
    b.UserId,
    COUNT(*) as TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges,
    MAX(b.Date) as MostRecentBadgeDate
  FROM Badges b
  WHERE b.Date >= TIMESTAMP '2020-01-01'
  GROUP BY b.UserId
),
TopTagExperts AS (
  SELECT
    te.OwnerUserId,
    te.TagName,
    te.TagUsageCount,
    te.AvgTagScore,
    t.Count as TagPopularity,
    RANK() OVER (PARTITION BY te.OwnerUserId ORDER BY te.TagUsageCount DESC, te.AvgTagScore DESC) as ExpertiseRank
  FROM TagExpertise te
  JOIN Tags t ON t.TagName = te.TagName
  WHERE te.TagUsageCount >= 3
)
SELECT 
  ui.Id as UserId,
  ui.DisplayName,
  ui.Reputation,
  ui.QuestionCount,
  ui.AnswerCount,
  ui.TotalQuestionScore,
  ui.TotalAnswerScore,
  ROUND((ui.TotalQuestionScore + ui.TotalAnswerScore) / NULLIF(CAST((ui.QuestionCount + ui.AnswerCount) AS NUMERIC), 0), 2) as AvgPostScore,
  COALESCE(aar.AcceptedAnswers, 0) as AcceptedAnswers,
  COALESCE(aar.TotalAnswers, 0) as TotalAnswers,
  ROUND(COALESCE(aar.AcceptedAnswers, 0) * 100.0 / NULLIF(COALESCE(aar.TotalAnswers, 0), 0), 2) as AcceptanceRate,
  COALESCE(aar.AvgAnswerScore, 0) as AvgAnswerScore,
  COALESCE(aar.MedianAnswerScore, 0) as MedianAnswerScore,
  COALESCE(vb.UpvotesGiven, 0) as UpvotesGiven,
  COALESCE(vb.DownvotesGiven, 0) as DownvotesGiven,
  COALESCE(vb.FavoritesGiven, 0) as FavoritesGiven,
  COALESCE(ca.CommentCount, 0) as CommentCount,
  COALESCE(ca.AvgCommentScore, 0) as AvgCommentScore,
  COALESCE(ba.TotalBadges, 0) as TotalBadges,
  COALESCE(ba.GoldBadges, 0) as GoldBadges,
  COALESCE(ba.SilverBadges, 0) as SilverBadges,
  COALESCE(ba.BronzeBadges, 0) as BronzeBadges,
  STRING_AGG(tte.TagName || '(' || CAST(tte.TagUsageCount AS VARCHAR) || ')', ', ' ORDER BY tte.TagName || '(' || CAST(tte.TagUsageCount AS VARCHAR) || ')') FILTER (WHERE tte.ExpertiseRank <= 5) as TopTags,
  EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ui.CreationDate)) / 86400 as DaysSinceJoining,
  ROUND((ui.QuestionCount + ui.AnswerCount) / NULLIF(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ui.CreationDate)) / 86400, 0), 3) as PostsPerDay
FROM UserInfluence ui
LEFT JOIN AnswerAcceptanceRate aar ON ui.Id = aar.OwnerUserId
LEFT JOIN VotingBehavior vb ON ui.Id = vb.UserId
LEFT JOIN CommentActivity ca ON ui.Id = ca.UserId
LEFT JOIN BadgeAchievements ba ON ui.Id = ba.UserId
LEFT JOIN TopTagExperts tte ON ui.Id = tte.OwnerUserId
GROUP BY 
  ui.Id, ui.DisplayName, ui.Reputation, ui.QuestionCount, ui.AnswerCount, 
  ui.TotalQuestionScore, ui.TotalAnswerScore, ui.CreationDate,
  aar.AcceptedAnswers, aar.TotalAnswers, aar.AvgAnswerScore, aar.MedianAnswerScore,
  vb.UpvotesGiven, vb.DownvotesGiven, vb.FavoritesGiven,
  ca.CommentCount, ca.AvgCommentScore,
  ba.TotalBadges, ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges,
  tte.TagName, tte.TagUsageCount, tte.ExpertiseRank
HAVING ui.Reputation > 1000
ORDER BY 
  (ui.TotalQuestionScore + ui.TotalAnswerScore + COALESCE(ba.GoldBadges, 0) * 100 + COALESCE(ba.SilverBadges, 0) * 10) DESC,
  ui.Reputation DESC
LIMIT 100;