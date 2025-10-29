-- {"query": "7841.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1907} 
WITH UserActivityStats AS (
  SELECT 
    u.Id as UserId,
    u.Reputation,
    u.DisplayName,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT b.Id) as Badges,
    MAX(p.CreationDate) as LastPostDate,
    AVG(p.Score) as AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.CreationDate >= '2010-01-01'
  GROUP BY u.Id, u.Reputation, u.DisplayName
),
PostComplexity AS (
  SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.OwnerUserId,
    CASE 
      WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
        CASE WHEN p.AcceptedAnswerId IS NULL THEN 'Unanswered' ELSE 'Answered' END
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END as PostStatus,
    CASE 
      WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN 
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
      ELSE 0 
    END as TagCount,
    CASE 
      WHEN p.Score >= 100 THEN 'High'
      WHEN p.Score >= 50 THEN 'Medium'
      WHEN p.Score >= 10 THEN 'Low'
      ELSE 'Very Low'
    END as ScoreCategory,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostRank,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore
  FROM Posts p
  WHERE p.CreationDate >= '2010-01-01'
    AND p.PostTypeId IN (1, 2)
),
UserRankings AS (
  SELECT 
    UserId,
    Reputation,
    DisplayName,
    TotalPosts,
    Questions,
    Answers,
    Comments,
    Badges,
    LastPostDate,
    AvgPostScore,
    DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank,
    DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as PostRank,
    DENSE_RANK() OVER (ORDER BY Badges DESC) as BadgeRank
  FROM UserActivityStats
),
EngagementMetrics AS (
  SELECT 
    u.Id as UserId,
    u.DisplayName,
    COALESCE(p.AnswerCount, 0) as UserAnswers,
    COALESCE(p.QuestionCount, 0) as UserQuestions,
    COALESCE(c.CommentCount, 0) as UserComments,
    CASE 
      WHEN COALESCE(p.AnswerCount, 0) + COALESCE(p.QuestionCount, 0) + COALESCE(c.CommentCount, 0) > 100 THEN 'High Engagement'
      WHEN COALESCE(p.AnswerCount, 0) + COALESCE(p.QuestionCount, 0) + COALESCE(c.CommentCount, 0) > 50 THEN 'Medium Engagement'
      ELSE 'Low Engagement'
    END as EngagementLevel,
    (COALESCE(p.AnswerCount, 0) * 2 + COALESCE(p.QuestionCount, 0) * 3 + COALESCE(c.CommentCount, 0)) as EngagementScore
  FROM Users u
  LEFT JOIN (
    SELECT 
      OwnerUserId,
      COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) as QuestionCount,
      COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) as AnswerCount
    FROM Posts 
    WHERE CreationDate >= '2010-01-01'
    GROUP BY OwnerUserId
  ) p ON u.Id = p.OwnerUserId
  LEFT JOIN (
    SELECT 
      UserId,
      COUNT(*) as CommentCount
    FROM Comments
    WHERE CreationDate >= '2010-01-01'
    GROUP BY UserId
  ) c ON u.Id = c.UserId
  WHERE u.Reputation > 100
),
TopPerformerWithHistory AS (
  SELECT 
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalPosts,
    ur.Questions,
    ur.Answers,
    ur.Comments,
    ur.Badges,
    ur.RepRank,
    ur.PostRank,
    ur.BadgeRank,
    CASE 
      WHEN ur.RepRank <= 10 THEN 'Top 10'
      WHEN ur.RepRank <= 50 THEN 'Top 50'
      ELSE 'Regular'
    END as RepTier,
    CASE 
      WHEN ur.PostRank <= 10 THEN 'Top 10 Posters'
      WHEN ur.PostRank <= 50 THEN 'Top 50 Posters'
      ELSE 'Regular Poster'
    END as PostTier
  FROM UserRankings ur
  WHERE ur.RepRank <= 100 OR ur.PostRank <= 100 OR ur.BadgeRank <= 100
)
SELECT 
  tp.UserId,
  tp.DisplayName,
  tp.Reputation,
  tp.TotalPosts,
  tp.Questions,
  tp.Answers,
  tp.Comments,
  tp.Badges,
  tp.RepRank,
  tp.PostRank,
  tp.BadgeRank,
  tp.RepTier,
  tp.PostTier,
  CASE 
    WHEN tp.RepRank BETWEEN 1 AND 5 THEN '🏆 Elite'
    WHEN tp.RepRank BETWEEN 6 AND 10 THEN '🥈 High Achiever'
    WHEN tp.RepRank BETWEEN 11 AND 50 THEN '🥉 Mid-tier'
    WHEN tp.RepRank > 50 THEN '🏅 Regular Member'
    ELSE '📝 New Member'
  END as ReputationTier,
  CASE 
    WHEN tp.RepTier IN ('Top 10', 'Top 50') THEN 
      CASE 
        WHEN tp.RepRank <= 10 THEN '👑 Top 10 Member'
        WHEN tp.RepRank <= 50 THEN '🌟 Top 50 Member'
        ELSE '✨ Top 100 Member'
      END
    ELSE '📊 Other Member'
  END as SpecialRanking,
  CASE 
    WHEN tp.BadgeRank <= 10 THEN '🏆 Badge Collection Master'
    WHEN tp.BadgeRank <= 50 THEN '🥇 Badge Enthusiast'
    ELSE '🥈 Badge Supporter'
  END as BadgeRecognition,
  CASE 
    WHEN tp.TotalPosts >= 500 THEN '🔥 Legendary Poster'
    WHEN tp.TotalPosts >= 200 THEN '💥 Active Poster'
    WHEN tp.TotalPosts >= 100 THEN '⚡ Frequent Poster'
    ELSE '📝 New Poster'
  END as PosterStatus,
  EXTRACT(YEAR FROM tp.LastPostDate) as LastPostYear,
  COALESCE(e.EngagementLevel, 'No Activity') as EngagementLevel,
  CASE 
    WHEN e.EngagementLevel = 'High Engagement' THEN '📈 High Activity'
    WHEN e.EngagementLevel = 'Medium Engagement' THEN '📊 Medium Activity'
    ELSE '📉 Low Activity'
  END as ActivityRating,
  CASE 
    WHEN (tp.Reputation > 10000 AND tp.TotalPosts > 500) OR 
         (tp.Reputation > 5000 AND tp.TotalPosts > 1000) OR 
         (tp.Reputation > 1000 AND tp.TotalPosts > 2000) THEN '👑 Elite Contributor'
    WHEN tp.TotalPosts > 200 AND tp.Reputation > 1000 THEN '📊 Active Contributor'
    WHEN tp.TotalPosts > 50 AND tp.Reputation > 500 THEN '🔥 Regular Contributor'
    ELSE '📝 New Contributor'
  END as ContributionRating
FROM TopPerformerWithHistory tp
LEFT JOIN EngagementMetrics e ON tp.UserId = e.UserId
WHERE tp.Reputation > 1000
  AND tp.LastPostDate >= '2020-01-01'
  AND COALESCE(tp.TotalPosts, 0) >= 10
ORDER BY 
  tp.RepRank,
  tp.PostRank,
  tp.BadgeRank,
  tp.TotalPosts DESC
LIMIT 500;