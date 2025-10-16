WITH UserMetrics AS (
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
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score END) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.FavoriteCount) AS MaxFavoritesOnAPost
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    WHERE
        u.CreationDate < (CAST('2024-10-01' AS DATE) - INTERVAL '3' YEAR) AND u.Reputation > 1000
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe
),
BadgeAnalysis AS (
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
    SELECT
        ph.UserId
    FROM
        PostHistory ph
    JOIN
        Posts p ON ph.PostId = p.Id
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6)
        AND ph.UserId != p.OwnerUserId
    GROUP BY
        ph.UserId
    HAVING
        COUNT(*) > 10
    UNION
    SELECT
        p.OwnerUserId AS UserId
    FROM
        PostLinks pl
    JOIN
        Posts p ON p.Id = pl.PostId
    WHERE
        pl.LinkTypeId = 3
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
    HAVING
        COUNT(*) > 5
)
SELECT
    um.DisplayName,
    um.Reputation,
    ba.GoldBadges,
    um.QuestionCount,
    um.AnswerCount,
    (
        um.Reputation * 0.4
        + COALESCE(um.TotalViews, 0) * 0.1
        + COALESCE(ba.GoldBadges, 0) * 100
        + COALESCE(um.AvgPostScore, 0) * 10
        - (
            EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - um.LastAccessDate))
            / 86400
          )
    ) AS InfluenceScore,
    (
        SELECT p.Title
        FROM Posts p
        WHERE p.OwnerUserId = um.UserId AND p.PostTypeId = 1
        ORDER BY p.Score DESC, p.FavoriteCount DESC NULLS LAST
        LIMIT 1
    ) AS TopQuestionTitle,
    CUME_DIST() OVER (PARTITION BY EXTRACT(YEAR FROM um.CreationDate) ORDER BY um.Reputation) AS ReputationPercentileInCohort,
    UPPER(COALESCE(SUBSTRING(um.Location FROM '[^,]+'), 'UNKNOWN')) AS Country,
    LENGTH(um.AboutMe) AS AboutMeLength,
    EXISTS (
        SELECT 1
        FROM Posts ans
        JOIN PostLinks pl ON ans.ParentId = pl.PostId
        WHERE ans.OwnerUserId = um.UserId AND ans.PostTypeId = 2 AND pl.LinkTypeId = 3
    ) AS AnsweredThenMarkedDuplicate,
    EXTRACT(YEAR FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - um.CreationDate)) AS YearsOnSite
FROM
    UserMetrics um
JOIN
    BadgeAnalysis ba ON um.UserId = ba.UserId
JOIN
    AdvancedCommunityContributors acc ON um.UserId = acc.UserId
WHERE
    um.AnswerCount > um.QuestionCount
    AND um.AvgPostScore > (
        SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1,2)
    )
    AND ba.FirstGoldBadgeDate < (um.CreationDate + INTERVAL '2' YEAR)
    AND um.Location IS NOT NULL AND um.Location NOT LIKE '%Earth%'
    AND (um.QuestionCount > 20 OR um.AnswerCount > 100)
    AND um.AboutMe LIKE '%SQL%'
GROUP BY
    um.DisplayName,
    um.Reputation,
    ba.GoldBadges,
    um.QuestionCount,
    um.AnswerCount,
    um.TotalViews,
    um.AvgPostScore,
    um.LastAccessDate,
    um.UserId,
    um.CreationDate,
    um.Location,
    um.AboutMe
ORDER BY
    InfluenceScore DESC,
    ReputationPercentileInCohort DESC
LIMIT 200;