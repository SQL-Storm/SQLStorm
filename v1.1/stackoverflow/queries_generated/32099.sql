-- {"query": "32099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 598} 

WITH TopContributors AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        SUM(p.ViewCount) AS TotalPostViews,
        SUM(vb.BountyAmount) AS TotalBountyEarned
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes vb ON vb.UserId = u.Id AND vb.VoteTypeId = 9
    WHERE
        u.CreationDate >= '2023-01-01'
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(DISTINCT p.Id) > 5
    ORDER BY
        TotalPostViews DESC,
        TotalBountyEarned DESC
    LIMIT 10
),
HighImpactPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS Author,
        p.Score,
        v2.UpVotes,
        v3.DownVotes,
        pl.Count AS LinkCount,
        COALESCE(b.BadgeCount, 0) AS BadgeCount
    FROM
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS UpVotes FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) v2 ON p.Id = v2.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS DownVotes FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) v3 ON p.Id = v3.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS Count FROM PostLinks GROUP BY PostId) pl ON p.Id = pl.PostId
    LEFT JOIN
        (SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId) b ON u.Id = b.UserId
    WHERE
        p.Score > 100
    ORDER BY
        (v2.UpVotes - v3.DownVotes) DESC,
        pl.Count DESC
    LIMIT 10
)
SELECT 
    tc.UserName,
    tc.PostsCount,
    tc.CommentsCount,
    tc.TotalPostViews,
    tc.TotalBountyEarned,
    hp.PostId,
    hp.Title,
    hp.Author,
    hp.Score,
    hp.UpVotes,
    hp.DownVotes,
    hp.LinkCount,
    hp.BadgeCount
FROM 
    TopContributors tc
LEFT JOIN 
    HighImpactPosts hp ON tc.UserId = hp.PostId
ORDER BY
    tc.TotalPostViews DESC,
    hp.Score DESC;
