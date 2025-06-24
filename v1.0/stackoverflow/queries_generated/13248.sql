-- Performance benchmarking query for StackOverflow schema
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(v.VoteTypeId = 2) AS TotalUpvotes,
        SUM(v.VoteTypeId = 3) AS TotalDownvotes,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId AND v.UserId = u.Id
    GROUP BY
        u.Id
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount
    FROM
        Posts p
    WHERE
        p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
),
TopPosts AS (
    SELECT
        *,
        RANK() OVER (ORDER BY Score DESC) AS PostRank
    FROM
        PostMetrics
)
SELECT
    ua.DisplayName AS UserName,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalUpvotes,
    ua.TotalDownvotes,
    ua.LastPostDate,
    tp.Title AS TopPostTitle,
    tp.Score AS TopPostScore,
    tp.ViewCount AS TopPostViewCount
FROM
    UserActivity ua
LEFT JOIN
    TopPosts tp ON ua.UserId = tp.OwnerUserId
WHERE
    tp.PostRank = 1
ORDER BY
    ua.TotalPosts DESC
LIMIT 100;
