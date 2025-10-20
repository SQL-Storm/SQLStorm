WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        tag.TagName,
        COUNT(p.Id) AS PostCount,
        MAX(p.Score) AS MaxScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        SELECT 
            SUBSTR(Tags, 2, LENGTH(Tags) - 2) AS TagList,
            Id AS PostId
        FROM Posts
    ) posts_tags ON posts_tags.PostId = p.Id
    CROSS JOIN LATERAL (
        SELECT TRIM(t) AS TagName
        FROM (
            SELECT regexp_split_to_table(posts_tags.TagList, '><') AS t
        ) s
    ) tag
    WHERE u.Reputation > 1000
      AND tag.TagName IS NOT NULL
    GROUP BY u.Id, u.DisplayName, tag.TagName
),
UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostUpvotes AS (
    SELECT 
        p.OwnerUserId AS OwnerUserId,
        tag.TagName AS TagName,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN (
        SELECT 
            Id AS PostId,
            SUBSTR(Tags, 2, LENGTH(Tags) - 2) AS TagList
        FROM Posts
    ) posts_tags ON posts_tags.PostId = p.Id
    CROSS JOIN LATERAL (
        SELECT TRIM(t) AS TagName
        FROM (
            SELECT regexp_split_to_table(posts_tags.TagList, '><') AS t
        ) s
    ) tag
    GROUP BY p.OwnerUserId, tag.TagName
)
SELECT 
    aut.UserId,
    aut.DisplayName,
    aut.TagName,
    aut.PostCount,
    aut.MaxScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(pu.UpvoteCount, 0) AS UpvoteCount,
    ROUND(CAST(aut.PostCount * (1.0 + LN(aut.MaxScore + 1)) AS numeric), 2) AS ContributionScore,
    CASE 
        WHEN aut.PostCount > 100 THEN 'Top Contributor'
        WHEN aut.PostCount > 50 THEN 'Active Contributor'
        ELSE 'Emerging Contributor'
    END AS ContributorLevel
FROM ActiveUserTags aut
LEFT JOIN UserBadgeStats ubs ON aut.UserId = ubs.UserId
LEFT JOIN PostUpvotes pu ON pu.OwnerUserId = aut.UserId AND pu.TagName = aut.TagName
WHERE aut.TagRank <= 3
  AND (aut.PostCount > 10 OR COALESCE(ubs.GoldBadges, 0) > 0)
ORDER BY ContributionScore DESC
LIMIT 100;