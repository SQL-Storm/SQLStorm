-- {"query": "20034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1184} 
WITH UserActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.CreationDate AS ActivityDate,
        p.Score,
        p.PostTypeId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS TagName
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 -- Answers
      AND p.OwnerUserId IS NOT NULL
      AND q.Tags IS NOT NULL

    UNION ALL

    SELECT
        c.UserId,
        c.CreationDate AS ActivityDate,
        c.Score,
        -1 AS PostTypeId, -- Custom type for comments
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS TagName
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    JOIN Posts q ON p.ParentId = q.Id OR p.Id = q.Id -- Comment on answer or question
    WHERE c.UserId IS NOT NULL
      AND q.PostTypeId = 1
      AND q.Tags IS NOT NULL
),
UserTagPerformance AS (
    SELECT
        UserId,
        TagName,
        COUNT(*) AS ActivitiesInTag,
        SUM(Score) AS TotalScoreInTag,
        AVG(Score) AS AvgScoreInTag,
        MAX(ActivityDate) AS LastActivityInTag,
        MIN(ActivityDate) AS FirstActivityInTag,
        MAX(ActivityDate) - MIN(ActivityDate) AS EngagementDuration
    FROM UserActivity
    GROUP BY UserId, TagName
    HAVING COUNT(*) > 10 AND SUM(Score) > 0
),
RankedUsers AS (
    SELECT
        utp.UserId,
        u.DisplayName,
        u.Reputation,
        utp.TagName,
        utp.TotalScoreInTag,
        utp.ActivitiesInTag,
        utp.LastActivityInTag,
        utp.EngagementDuration,
        -- Window function to rank users within each tag
        DENSE_RANK() OVER (PARTITION BY utp.TagName ORDER BY utp.TotalScoreInTag DESC, utp.ActivitiesInTag DESC) AS TagRank,
        -- Window function to get the score of the previous ranked user
        LAG(utp.TotalScoreInTag, 1, 0) OVER (PARTITION BY utp.TagName ORDER BY utp.TotalScoreInTag DESC, utp.ActivitiesInTag DESC) AS PreviousUserScore,
        -- Correlated subquery to find user's gold badge count
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = utp.UserId AND b.Class = 1) AS GoldBadges,
        -- Calculation: score per day of engagement
        utp.TotalScoreInTag * 1.0 / (EXTRACT(EPOCH FROM utp.EngagementDuration) / 86400.0 + 1) AS ScorePerDay
    FROM UserTagPerformance utp
    JOIN Users u ON utp.UserId = u.Id
    WHERE u.Reputation > 1000 AND u.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
)
SELECT
    ru.DisplayName,
    ru.TagName,
    t.Count AS GlobalTagCount,
    ru.TagRank,
    ru.TotalScoreInTag,
    ru.TotalScoreInTag - ru.PreviousUserScore AS ScoreDiffToPrevRank,
    ru.ActivitiesInTag,
    ru.Reputation,
    ru.GoldBadges,
    ru.ScorePerDay,
    EXTRACT(YEAR FROM ru.LastActivityInTag) AS LastActivityYear,
    -- Complicated CASE statement with NULL logic and string manipulation
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%github.com%' THEN 'Has GitHub Profile'
        WHEN u.AboutMe IS NOT NULL THEN 'Has AboutMe'
        ELSE 'Profile Incomplete'
    END AS ProfileStatus,
    -- Another correlated subquery to find the user's most upvoted answer in that tag
    (SELECT p.Title
     FROM Posts p
     JOIN Posts a ON p.Id = a.ParentId
     WHERE a.OwnerUserId = ru.UserId
       AND a.PostTypeId = 2
       AND p.Tags LIKE ('<' || ru.TagName || '>')
     ORDER BY a.Score DESC
     LIMIT 1) AS TopAnswerTitleInTag
FROM RankedUsers ru
LEFT JOIN Tags t ON ru.TagName = t.TagName
LEFT JOIN Users u ON ru.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = ru.UserId AND ph.PostHistoryTypeId = 10 -- Closed posts
WHERE ru.TagRank <= 5
  AND t.Count > (SELECT AVG(Count) FROM Tags WHERE IsRequired = '1')
  AND ru.LastActivityInTag < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year')
  AND ph.Id IS NULL -- Filter out users who have voted to close posts
ORDER BY
    ru.TagName,
    ru.TagRank;