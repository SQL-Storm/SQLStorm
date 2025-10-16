WITH RecurringUsers AS (
    SELECT
        UserId,
        COUNT(*) AS BadgeCount,
        MIN(Date) AS FirstBadgeDate,
        MAX(Date) AS LastBadgeDate
    FROM
        Badges
    GROUP BY
        UserId
    HAVING
        COUNT(*) > 10
),
PopularPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        COALESCE(CAST(p.Score AS NUMERIC) / NULLIF(CAST(p.ViewCount AS NUMERIC), 0), 0) AS ScorePerView,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS PopRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.ViewCount > 1000
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Votes pv ON p.Id = pv.PostId
    GROUP BY
        u.Id, u.DisplayName
),
PotentialDuplicates AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        CASE
            WHEN p1.Score = p2.Score THEN 1
            ELSE 0
        END AS ScoreMatch
    FROM
        PostLinks pl
        JOIN Posts p1 ON pl.PostId = p1.Id
        JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE
        pl.LinkTypeId = 3
        AND p1.OwnerUserId <> p2.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    us.TotalUpVotes,
    us.TotalDownVotes,
    CASE WHEN ru.UserId IS NOT NULL THEN 'Frequent' ELSE 'Other' END AS UserCategory,
    CASE 
        WHEN pp.PopRank <= 10 THEN 'Top 10'
        WHEN pp.PopRank <= 50 THEN 'Top 50'
        ELSE 'Others'
    END AS PopularityRank,
    AVG(COALESCE(pp.ScorePerView, 0)) OVER (
        PARTITION BY CASE 
            WHEN us.TotalPosts > 0 THEN ROUND(CAST(us.TotalUpVotes AS NUMERIC) / NULLIF(CAST(us.TotalPosts AS NUMERIC), 0), 2)
            ELSE 0
        END
    ) AS AvgScorePerView
FROM
    Users u
    LEFT JOIN RecurringUsers ru ON ru.UserId = u.Id
    LEFT JOIN UserPostStats us ON us.UserId = u.Id
    LEFT JOIN Posts pt ON pt.OwnerUserId = u.Id
    LEFT JOIN PopularPosts pp ON pt.Id = pp.PostId
    LEFT JOIN PotentialDuplicates pd ON pt.Id = pd.PostId
WHERE
    u.CreationDate > DATE '2010-01-01'
    AND (us.TotalUpVotes - us.TotalDownVotes) > 100
    AND EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = u.Id
        AND b.Date BETWEEN u.CreationDate AND u.LastAccessDate
    )
GROUP BY
    u.Id,
    u.DisplayName,
    us.TotalUpVotes,
    us.TotalDownVotes,
    us.TotalPosts,
    ru.UserId,
    pp.PopRank,
    pp.ScorePerView,
    u.CreationDate,
    u.LastAccessDate,
    u.Reputation
ORDER BY
    us.TotalUpVotes DESC,
    u.Reputation DESC;