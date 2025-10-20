-- {"query": "9078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 1301} 
WITH
-- Identify recent activity on posts (questions and answers)
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.LastActivityDate,
        u.Id        AS OwnerUserId,
        u.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u
        ON p.OwnerUserId = u.Id
    WHERE p.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),

-- Count badges per user and rank them by count
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

RankedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        bc.TotalBadges,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, bc.TotalBadges DESC) AS UserRank
    FROM Users u
    LEFT JOIN BadgeCounts bc
        ON u.Id = bc.UserId
    WHERE u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),

-- Compute tag usage statistics
TagUsage AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT pt.Id) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score)    AS AvgScore,
        MAX(p.Score)    AS MaxScore
    FROM Tags t
    INNER JOIN Posts p
        ON p.PostTypeId = 1
       AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    INNER JOIN Posts pt
        ON pt.Id = p.Id
    GROUP BY t.TagName
),

-- Find duplicate links between posts
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType
    FROM PostLinks pl
    JOIN LinkTypes lt
        ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),

-- Combine recent activity and top users with UNION
CombinedActivity AS (
    SELECT
        ra.PostId,
        ra.PostTypeId,
        ra.LastActivityDate,
        ru.DisplayName    AS UserName,
        ru.UserRank       AS RankOrRowNum,
        'RecentActivity'  AS Source
    FROM RecentActivity ra
    JOIN RankedUsers ru
        ON ra.OwnerUserId = ru.Id
    WHERE ra.rn <= 5

    UNION ALL

    SELECT
        NULL        AS PostId,
        NULL        AS PostTypeId,
        NULL        AS LastActivityDate,
        ru.DisplayName       AS UserName,
        ru.UserRank          AS RankOrRowNum,
        'TopUsers'           AS Source
    FROM RankedUsers ru
    WHERE ru.UserRank <= 10
)

-- Final SELECT bringing it all together
SELECT
    ca.Source,
    ca.PostId,
    ca.PostTypeId,
    ca.LastActivityDate,
    ca.UserName,
    ca.RankOrRowNum,
    tu.TagName,
    tu.QuestionCount,
    tu.TotalViews,
    tu.AvgScore,
    tu.MaxScore,
    dl.RelatedPostId,
    dl.LinkType,
    -- correlated subquery: latest comment for posts in recent activity
    (
        SELECT c.Text
        FROM Comments c
        WHERE c.PostId = ca.PostId
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS LatestComment,
    -- string expression and NULL logic example
    COALESCE(u.WebsiteUrl, 'N/A') AS Website,
    CONCAT(u.DisplayName, ' (', u.Reputation, ')') AS UserBadgeInfo
FROM CombinedActivity ca
LEFT JOIN TagUsage tu
    ON ca.Source = 'RecentActivity'
   AND tu.QuestionCount > 100
LEFT JOIN DuplicateLinks dl
    ON dl.PostId = ca.PostId
LEFT JOIN Users u
    ON u.DisplayName = ca.UserName
ORDER BY ca.Source,
         ca.RankOrRowNum,
         ca.LastActivityDate DESC
;