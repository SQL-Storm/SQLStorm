-- {"query": "21005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1457} 

WITH ActiveUsers AS (
  SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM Users u
  INNER JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Reputation > 100 
    AND u.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    AND p.CreationDate > u.CreationDate
  GROUP BY u.Id, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) >= 5
),
TopBadgesPerUser AS (
  SELECT 
    b.UserId,
    b.Name AS BadgeName,
    b.Date,
    b.Class,
    ROW_NUMBER() OVER (
      PARTITION BY b.UserId 
      ORDER BY 
        CASE WHEN b.Class = 1 THEN 3 ELSE b.Class END DESC,
        b.Date DESC
    ) AS BadgeRank
  FROM Badges b
  INNER JOIN ActiveUsers au ON b.UserId = au.UserId
  WHERE b.TagBased = 0  -- Named badges only
),
RecentPostsWithMetrics AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.Title,
    p.Tags,
    COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
    CASE 
      WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 
        EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 3600
      ELSE NULL 
    END AS HoursToClosure,
    -- Complex string manipulation for tag analysis
    CASE 
      WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN
        LENGTH(REGEXP_REPLACE(p.Tags, '<[^>]+>', '', 'g'))
      ELSE 0 
    END AS TagComplexityScore
  FROM Posts p
  WHERE p.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    AND (p.PostTypeId IN (1, 2) OR (p.PostTypeId IN (4, 5) AND p.Score > 10))
),
UserEngagementMetrics AS (
  SELECT 
    au.UserId,
    au.PostCount,
    au.QuestionCount,
    au.AnswerCount,
    au.Reputation,
    -- Window function for ranking users by engagement
    RANK() OVER (
      ORDER BY 
        (au.QuestionCount * 2 + au.AnswerCount) * LOG(au.Reputation + 1) DESC
    ) AS EngagementRank,
    AVG(rpwm.HoursToClosure) FILTER (WHERE rpwm.HoursToClosure IS NOT NULL) AS AvgQuestionLifetimeHours,
    -- Correlated subquery for average post performance
    (SELECT AVG(rpwm2.Score) 
     FROM RecentPostsWithMetrics rpwm2 
     WHERE rpwm2.OwnerUserId = au.UserId 
       AND rpwm2.PostTypeId = 1) AS AvgQuestionScore
  FROM ActiveUsers au
  LEFT JOIN RecentPostsWithMetrics rpwm ON au.UserId = rpwm.OwnerUserId
  GROUP BY au.UserId, au.PostCount, au.QuestionCount, au.AnswerCount, au.Reputation
)
SELECT 
  uem.UserId,
  u.DisplayName,
  u.Location,
  u.Reputation,
  uem.PostCount,
  uem.QuestionCount,
  uem.AnswerCount,
  uem.EngagementRank,
  uem.AvgQuestionScore,
  uem.AvgQuestionLifetimeHours,
  -- Complex calculation for engagement index
  ROUND(
    (uem.QuestionCount * 3 + uem.AnswerCount * 2 + uem.PostCount * COALESCE(tbp.Name, 'None'))::numeric * 
    POWER(uem.Reputation, 0.5) / 
    GREATEST(EXTRACT(DAY FROM (CURRENT_DATE - u.UserCreationDate)), 1),
    2
  ) AS EngagementIndex,
  -- String concatenation with NULL handling
  COALESCE(
    CONCAT(
      'Q:', uem.QuestionCount::text, 
      ' A:', uem.AnswerCount::text, 
      CASE WHEN tbp.BadgeName IS NOT NULL 
           THEN CONCAT(' TopBadge:', LEFT(tbp.BadgeName, 20))
           ELSE ' NoTopBadge' 
      END
    ),
    'BasicUser'
  ) AS UserProfileSummary,
  -- Set operation within scalar subquery for vote analysis
  (SELECT 
     CASE 
       WHEN upvote_count > downvote_count * 2 THEN 'UpvoteHeavy'
       WHEN downvote_count > upvote_count THEN 'DownvoteHeavy'
       ELSE 'Balanced'
     END
   FROM (
     SELECT 
       COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvote_count,
       COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvote_count
     FROM Votes v
     WHERE v.UserId = uem.UserId
       AND v.CreationDate > CURRENT_DATE - INTERVAL '3 months'
   ) vote_stats
  ) AS RecentVotePattern,
  -- Window function for percentile ranking
  PERCENT_RANK() OVER (
    ORDER BY uem.Reputation DESC
  ) AS ReputationPercentile,
  -- NULL logic with complex CASE
  CASE 
    WHEN uem.AvgQuestionLifetimeHours IS NULL OR uem.AvgQuestionLifetimeHours > 168 THEN 'LongLived'
    WHEN uem.AvgQuestionLifetimeHours <= 24 THEN 'QuickClose'
    WHEN uem.AvgQuestionLifetimeHours IS NOT NULL THEN 'Moderate'
    ELSE 'NoQuestions'
  END AS QuestionClosureCategory
FROM UserEngagementMetrics uem
INNER JOIN Users u ON uem.UserId = u.Id
LEFT OUTER JOIN TopBadgesPerUser tbp ON uem.UserId = tbp.UserId AND tbp.BadgeRank = 1
WHERE uem.EngagementRank <= 1000  -- Top 1000 most engaged users
  AND (uem.QuestionCount > 0 OR uem.AnswerCount > 10)  -- Active in questions or answers
  AND u.Location IS NOT NULL 
    AND LENGTH(TRIM(u.Location)) > 0  -- Has meaningful location
    AND NOT (u.DisplayName ILIKE '%bot%' OR u.DisplayName ILIKE '%test%')  -- Exclude bots
ORDER BY uem.EngagementRank ASC, uem.Reputation DESC
LIMIT 500;
