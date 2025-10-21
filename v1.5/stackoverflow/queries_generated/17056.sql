-- {"query": "17056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 133095, "output_tokens": 132464} 

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.CreationDate)) * 12 + 
        EXTRACT(MONTH FROM AGE(CURRENT_DATE, u.CreationDate)) AS AccountAgeMonths,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        STRING_AGG(DISTINCT 
            CASE WHEN b.Class = 1 THEN b.Name END, 
            ', ' ORDER BY b.Name
        ) AS GoldBadges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) 
                          ORDER BY u.Reputation DESC) AS YearCohortRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
      AND u.Reputation > 100
      AND (u.Location IS NULL OR u.Location NOT LIKE '%test%')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
PopularTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        MAX(p.Score) FILTER (WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '90 days') AS RecentMaxScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE t.Count >= 1000
      AND p.Score > 0
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.OwnerUserId) > 50
),
AnswerAnalysis AS (
    SELECT 
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        q.Id AS QuestionId,
        q.Score AS QuestionScore,
        q.ViewCount,
        CASE 
            WHEN a.Id = q.AcceptedAnswerId THEN 'Accepted'
            WHEN a.Score > COALESCE((
                SELECT MAX(a2.Score) 
                FROM Posts a2 
                WHERE a2.ParentId = q.Id 
                  AND a2.Id != a.Id
            ), 0) THEN 'TopScored'
            WHEN a.Score >= 5 THEN 'HighlyVoted'
            ELSE 'Regular'
        END AS AnswerStatus,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 AS HoursToAnswer,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC) AS UserAnswerRank,
        COALESCE(NULLIF(TRIM(SUBSTRING(q.Tags FROM 2 FOR POSITION('><' IN q.Tags) - 2)), ''), 'untagged') AS PrimaryTag
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
      AND q.PostTypeId = 1
      AND a.OwnerUserId IS NOT NULL
      AND a.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
),
UserActivity AS (
    SELECT DISTINCT
        um.Id,
        um.DisplayName,
        um.Reputation,
        um.ReputationRank,
        um.Location,
        um.AccountAgeMonths,
        um.TotalPosts,
        um.QuestionCount,
        um.AnswerCount,
        um.AvgPostScore,
        COALESCE(um.GoldBadges, 'None') AS GoldBadges,
        COUNT(aa.AnswerId) AS QualityAnswers,
        AVG(aa.HoursToAnswer) FILTER (WHERE aa.AnswerStatus = 'Accepted') AS AvgTimeToAcceptedAnswer,
        STRING_AGG(DISTINCT pt.TagName, ', ' ORDER BY pt.TagName) 
            FILTER (WHERE pt.TagUsageCount > 5000) AS ExpertiseTags,
        MAX(CASE WHEN aa.UserAnswerRank = 1 THEN aa.AnswerScore END) AS BestAnswerScore,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.UserId = um.Id 
               AND c.Score >= 5
               AND c.CreationDate >= CURRENT_DATE - INTERVAL '1 year'),
            0
        ) AS RecentPopularComments,
        EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.UserId = um.Id 
              AND ph.PostHistoryTypeId IN (4, 5, 6)
              AND ph.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        ) AS RecentlyActive
    FROM UserMetrics um
    LEFT JOIN AnswerAnalysis aa ON um.Id = aa.OwnerUserId
    LEFT JOIN PopularTags pt ON aa.PrimaryTag = pt.TagName
    WHERE um.ReputationRank <= 1000
       OR um.YearCohortRank <= 10
       OR um.QuestionCount + um.AnswerCount >= 100
    GROUP BY um.Id, um.DisplayName, um.Reputation, um.ReputationRank, 
             um.Location, um.AccountAgeMonths, um.TotalPosts, um.QuestionCount,
             um.AnswerCount, um.AvgPostScore, um.GoldBadges, um.YearCohortRank
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    ua.ReputationRank,
    UPPER(SUBSTRING(ua.Location FROM 1 FOR 2)) || 
        LOWER(SUBSTRING(ua.Location FROM 3)) AS FormattedLocation,
    ua.AccountAgeMonths || ' months' AS AccountAge,
    ua.TotalPosts,
    ROUND(ua.AvgPostScore::numeric, 2) AS AvgPostScore,
    ua.GoldBadges,
    ua.QualityAnswers,
    CASE 
        WHEN ua.AvgTimeToAcceptedAnswer IS NULL THEN 'No accepted answers'
        WHEN ua.AvgTimeToAcceptedAnswer < 1 THEN 'Lightning fast (<1 hr)'
        WHEN ua.AvgTimeToAcceptedAnswer < 24 THEN 'Fast (' || ROUND(ua.AvgTimeToAcceptedAnswer::numeric, 1) || ' hrs)'
        WHEN ua.AvgTimeToAcceptedAnswer < 168 THEN 'Normal (' || ROUND(ua.AvgTimeToAcceptedAnswer/24::numeric, 1) || ' days)'
        ELSE 'Slow (>' || ROUND(ua.AvgTimeToAcceptedAnswer/24::numeric, 0) || ' days)'
    END AS ResponseSpeed,
    COALESCE(ua.ExpertiseTags, 'No popular tags') AS ExpertiseTags,
    ua.BestAnswerScore,
    ua.RecentPopularComments,
    ua.RecentlyActive,
    CASE 
        WHEN ua.Reputation > 100000 THEN 'Legendary'
        WHEN ua.Reputation > 25000 THEN 'Trusted'
        WHEN ua.Reputation > 10000 THEN 'Established'
        WHEN ua.Reputation > 3000 THEN 'Experienced'
        WHEN ua.Reputation > 1000 THEN 'Promising'
        ELSE 'Rising'
    END AS UserTier,
    ROUND(
        (ua.QualityAnswers::numeric / NULLIF(ua.AnswerCount, 0) * 100)::numeric, 
        1
    ) AS QualityAnswerPercentage
FROM UserActivity ua
WHERE ua.TotalPosts > 0
  AND (ua.RecentlyActive = true OR ua.RecentPopularComments > 2)
  AND NOT (ua.QuestionCount = 0 AND ua.AnswerCount < 5)
ORDER BY 
    ua.ReputationRank ASC,
    ua.QualityAnswers DESC,
    ua.BestAnswerScore DESC NULLS LAST
LIMIT 100;
