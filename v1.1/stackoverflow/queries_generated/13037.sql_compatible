WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT ph.Id) AS EditsCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(p.Score) AS TotalPostScore,
        AVG(COALESCE(NULLIF(u.Reputation, 0), 0)) AS AvgReputation
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    WHERE 
        u.CreationDate >= DATE '2021-01-01'
    GROUP BY 
        u.Id
),
RankedUsers AS (
    SELECT 
        UserId,
        PostsCount,
        EditsCount,
        UpvotesGiven,
        DownvotesGiven,
        TotalPostScore,
        AvgReputation,
        RANK() OVER (ORDER BY TotalPostScore DESC, UpvotesGiven DESC) AS UserRank
    FROM 
        UserActivity
)
SELECT 
    u.DisplayName,
    u.Reputation,
    ru.PostsCount,
    ru.EditsCount,
    ru.UpvotesGiven,
    ru.DownvotesGiven,
    ru.TotalPostScore,
    ru.AvgReputation,
    'Top ' || CAST(CEIL(PERCENT_RANK() OVER (ORDER BY ru.TotalPostScore DESC, ru.UpvotesGiven DESC) * 100) AS VARCHAR) || '%' AS UserPercentile,
    CASE
        WHEN b.Class = 1 THEN 'Gold'
        WHEN b.Class = 2 THEN 'Silver'
        ELSE 'Bronze'
    END AS BadgeClass
FROM 
    RankedUsers ru
JOIN 
    Users u ON ru.UserId = u.Id
LEFT JOIN LATERAL (
    SELECT 
        b1.Class
    FROM 
        Badges b1
    WHERE 
        b1.UserId = ru.UserId
    ORDER BY 
        b1.Class ASC
    LIMIT 1
) b ON TRUE
WHERE 
    ru.UserRank <= 100
    AND ru.PostsCount > (SELECT AVG(PostsCount) FROM UserActivity)
GROUP BY
    u.DisplayName,
    u.Reputation,
    ru.PostsCount,
    ru.EditsCount,
    ru.UpvotesGiven,
    ru.DownvotesGiven,
    ru.TotalPostScore,
    ru.AvgReputation,
    b.Class,
    ru.UserRank
ORDER BY 
    ru.UserRank;