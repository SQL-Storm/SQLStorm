-- {"query": "1091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 559} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN p.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalPosts,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalComments,
        SUM(CASE WHEN v.Id IS NOT NULL THEN 1 ELSE 0 END) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(u.Reputation) AS AvgReputation
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.CreationDate >= '2020-01-01'
    GROUP BY
        u.Id, u.DisplayName
),
RankedUserActivity AS (
    SELECT
        *,
        RANK() OVER (ORDER BY TotalPosts DESC, TotalComments DESC, TotalVotes DESC) AS ActivityRank
    FROM
        UserActivity
),
TopUsers AS (
    SELECT
        UserId,
        DisplayName,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        AvgReputation
    FROM
        RankedUserActivity
    WHERE
        ActivityRank <= 10
)
SELECT
    tu.DisplayName,
    tu.TotalPosts,
    tu.TotalComments,
    tu.TotalVotes,
    tu.TotalBadges,
    tu.AvgReputation,
    COALESCE(ph.EditCount, 0) AS TotalPostEdits,
    COALESCE(pl.LinkCount, 0) AS TotalPostLinks
FROM
    TopUsers tu
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        COUNT(ph.Id) AS EditCount
    FROM
        Posts p
    JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY
        p.OwnerUserId
) ph ON tu.UserId = ph.OwnerUserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        COUNT(pl.Id) AS LinkCount
    FROM
        Posts p
    JOIN
        PostLinks pl ON p.Id = pl.PostId
    GROUP BY
        p.OwnerUserId
) pl ON tu.UserId = pl.OwnerUserId
ORDER BY
    tu.TotalPosts DESC;