-- {"query": "20098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1346} 

WITH UserMetrics AS (
    -- CTE 1: Aggregate user-level statistics like post counts, average scores, and comment activity
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.FavoriteCount) AS MaxFavoritesOnAPost
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    WHERE
        u.CreationDate < (CURRENT_DATE - INTERVAL '3 year') AND u.Reputation > 1000
    GROUP BY
        u.Id
),
BadgeAnalysis AS (
    -- CTE 2: Analyze user badges, calculating counts and ranking users by their gold badge acquisitions
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(CASE WHEN Class = 1 THEN Date END) AS FirstGoldBadgeDate,
        DENSE_RANK() OVER (ORDER BY SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) DESC) AS GoldBadgeRank
    FROM
        Badges
    GROUP BY
        UserId
    HAVING
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) > 0
),
AdvancedCommunityContributors AS (
    -- CTE 3: Identify users who have performed advanced community actions, like editing others' posts or linking duplicates
    SELECT
        ph.UserId
    FROM
        PostHistory ph
    JOIN
        Posts p ON ph.PostId = p.Id
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
        AND ph.UserId != p.OwnerUserId
    GROUP BY
        ph.UserId
    HAVING
        COUNT(*) > 10 -- At least 10 edits on others' posts
    UNION
    SELECT
        p.OwnerUserId
    FROM
        PostLinks pl
    JOIN
        Posts p ON p.Id = pl.PostId
    WHERE
        pl.LinkTypeId = 3 -- Duplicate
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
    HAVING
        COUNT(*) > 5 -- Marked at least 5 posts as duplicates
)
SELECT
    um.DisplayName,
    um.Reputation,
    ba.GoldBadges,
    um.QuestionCount,
    um.AnswerCount,
    -- Complex calculated "Influence Score"
    (um.Reputation * 0.4) + (um.TotalViews * 0.1) + (ba.GoldBadges * 100) + (um.AvgPostScore * 10) - (EXTRACT(EPOCH FROM (NOW() - um.LastAccessDate)) / 86400) AS InfluenceScore,
    -- Correlated subquery to find the title of the user's highest-scoring question
    (SELECT p.Title FROM Posts p WHERE p.OwnerUserId = um.UserId AND p.PostTypeId = 1 ORDER BY p.Score DESC, p.FavoriteCount DESC NULLS LAST LIMIT 1) AS TopQuestionTitle,
    -- Window function to calculate reputation percentile within the user's creation year cohort
    CUME_DIST() OVER (PARTITION BY EXTRACT(YEAR FROM um.CreationDate) ORDER BY um.Reputation) AS ReputationPercentileInCohort,
    -- String manipulation on user location and AboutMe
    UPPER(COALESCE(SUBSTRING(um.Location FROM '[^,]+'), 'UNKNOWN')) AS Country,
    LENGTH(um.AboutMe) AS AboutMeLength,
    -- Check if user has answered a question that they themselves later marked as a duplicate of another
    EXISTS (
        SELECT 1
        FROM Posts ans
        JOIN PostLinks pl ON ans.ParentId = pl.PostId
        WHERE ans.OwnerUserId = um.UserId AND ans.PostTypeId = 2 AND pl.LinkTypeId = 3
    ) AS AnsweredThenMarkedDuplicate,
    EXTRACT(YEAR FROM AGE(NOW(), um.CreationDate)) AS YearsOnSite
FROM
    UserMetrics um
JOIN
    BadgeAnalysis ba ON um.UserId = ba.UserId
JOIN
    AdvancedCommunityContributors acc ON um.UserId = acc.UserId
WHERE
    um.AnswerCount > um.QuestionCount -- More answers than questions
    AND um.AvgPostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1,2)) -- Higher than average post score
    AND ba.FirstGoldBadgeDate < (um.CreationDate + INTERVAL '2 year') -- Earned first gold badge within 2 years of joining
    AND um.Location IS NOT NULL AND um.Location NOT LIKE '%Earth%'
    AND (um.QuestionCount > 20 OR um.AnswerCount > 100)
    AND um.AboutMe LIKE '%SQL%'
ORDER BY
    InfluenceScore DESC,
    ReputationPercentileInCohort DESC
LIMIT 200;
