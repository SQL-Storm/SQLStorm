-- {"query": "50008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1093} 
WITH TagStats AS (
    -- CTE 1: Calculate statistics for each tag, identifying popular and niche tags
    SELECT
        Id,
        TagName,
        Count,
        WikiPostId,
        CASE
            WHEN Count > 10000 THEN 'Popular'
            WHEN Count > 1000 THEN 'Established'
            ELSE 'Niche'
        END AS TagCategory
    FROM Tags
    WHERE IsModeratorOnly = false AND IsRequired = false
),
UserContributionSummary AS (
    -- CTE 2: Aggregate user contributions (answers, questions, comments) and calculate quality metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0) AS AvgAnswerScore,
        COALESCE(SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1), 0) AS TotalFavoriteCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.UserId = u.Id
        ) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 -- Focus on established users
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) > 10 -- Users with at least 10 answers
),
UserBadgeRanks AS (
    -- CTE 3: Rank users based on their badge counts within different badge classes
    SELECT
        UserId,
        Class,
        COUNT(*) AS BadgeCount,
        RANK() OVER (PARTITION BY Class ORDER BY COUNT(*) DESC) AS BadgeRank
    FROM Badges
    GROUP BY UserId, Class
)
-- Main Query: Combine user stats, tag interactions, and badge rankings to identify influential experts in popular technologies
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.Location,
    ucs.AnswerCount,
    ucs.AvgAnswerScore,
    ucs.TotalFavoriteCount,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM Posts p_source
        JOIN PostLinks pl ON p_source.Id = pl.PostId
        WHERE p_source.OwnerUserId = ucs.UserId AND pl.LinkTypeId = 1
    ) AS LinksGenerated,
    (
        SELECT ts.TagCategory
        FROM Posts p_tags
        CROSS JOIN LATERAL unnest(string_to_array(substring(p_tags.Tags, 2, length(p_tags.Tags)-2), '><')) AS t(TagName)
        JOIN TagStats ts ON t.TagName = ts.TagName
        WHERE p_tags.OwnerUserId = ucs.UserId AND p_tags.PostTypeId = 2
        GROUP BY ts.TagCategory
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS PrimaryTagCategory,
    gold_badges.BadgeCount AS GoldBadges,
    silver_badges.BadgeCount AS SilverBadges,
    bronze_badges.BadgeCount AS BronzeBadges,
    (ucs.LastActivityDate - ucs.FirstPostDate) AS ActivePeriod,
    ROW_NUMBER() OVER (ORDER BY ucs.Reputation DESC, ucs.AvgAnswerScore DESC) AS OverallRank
FROM
    UserContributionSummary ucs
LEFT JOIN
    UserBadgeRanks gold_badges ON ucs.UserId = gold_badges.UserId AND gold_badges.Class = 1
LEFT JOIN
    UserBadgeRanks silver_badges ON ucs.UserId = silver_badges.UserId AND silver_badges.Class = 2
LEFT JOIN
    UserBadgeRanks bronze_badges ON ucs.UserId = bronze_badges.UserId AND bronze_badges.Class = 3
WHERE
    ucs.Location IS NOT NULL AND ucs.Location != ''
    AND EXISTS (
        -- Ensure user has accepted at least one answer, indicating engagement
        SELECT 1
        FROM Votes v
        WHERE v.UserId = ucs.UserId AND v.VoteTypeId = 1
    )
ORDER BY
    OverallRank
LIMIT 500;