-- {"query": "4830.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 829} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn_user_creation,
        RANK() OVER (ORDER BY p.Score DESC) as rank_global_score
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    WHERE
        p.Score > 0 AND p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT rp.PostId) AS NumberOfRankedPosts,
        SUM(rp.Score) AS TotalScoreOfRankedPosts,
        AVG(rp.Score) AS AverageScoreOfRankedPosts,
        MAX(rp.CreationDate) AS LatestRankedPostDate
    FROM
        Users u
    LEFT JOIN
        RankedPosts rp ON u.Id = rp.OwnerUserId
    WHERE rp.rn_user_creation <= 5
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount
    FROM
        Comments c
    GROUP BY
        c.PostId
),
PostLinkDetails AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType
    FROM
        PostLinks pl
    JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE
        lt.Name = 'Duplicate'
)
SELECT
    COALESCE(ua.DisplayName, 'Unknown User') AS UserDisplayName,
    ua.Reputation,
    rp.Title AS LatestPostTitle,
    rp.PostTypeName,
    rp.Score AS LatestPostScore,
    ua.NumberOfRankedPosts,
    ua.TotalScoreOfRankedPosts,
    ua.AverageScoreOfRankedPosts,
    ua.LatestRankedPostDate,
    CASE
        WHEN ua.LatestRankedPostDate IS NULL THEN 'No Recent High-Scoring Posts'
        WHEN DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - ua.LatestRankedPostDate) < 30 THEN 'Recently Active'
        ELSE 'Less Recently Active'
    END AS ActivityStatus,
    pc.CommentCount,
    CASE
        WHEN pc.CommentCount > 10 THEN 'High Comment Activity'
        WHEN pc.CommentCount > 5 THEN 'Moderate Comment Activity'
        ELSE 'Low Comment Activity'
    END AS CommentActivityLevel,
    pld.RelatedPostId AS DuplicateOfPostId,
    pld.LinkType AS LinkRelation
FROM
    UserActivity ua
JOIN
    RankedPosts rp ON ua.UserId = rp.OwnerUserId AND rp.rn_user_creation = 1
LEFT JOIN
    PostComments pc ON rp.PostId = pc.PostId
LEFT JOIN
    PostLinkDetails pld ON rp.PostId = pld.PostId
WHERE
    ua.NumberOfRankedPosts >= 2
    AND ua.AverageScoreOfRankedPosts > 5
    AND rp.rank_global_score <= 1000
ORDER BY
    ua.Reputation DESC, ua.AverageScoreOfRankedPosts DESC
LIMIT 100;