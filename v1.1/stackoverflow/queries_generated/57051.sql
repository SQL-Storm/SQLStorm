-- {"query": "57051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 615} 

WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount
    FROM
        Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostHistory ph ON p.Id= ph.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        u.Id,
        u.DisplayName
    ORDER BY
        PostCount DESC
    LIMIT 10
),
ActiveTags AS (
    SELECT
        p.Tags,
        COUNT(p.Id) AS TagCount,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 1
        AND v.VoteTypeId = 2
    GROUP BY
        p.Tags
    ORDER BY
        TotalViews DESC
    LIMIT 10
),
CommentsAnalysis AS (
    SELECT
        c.postId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM
        Comments c
    JOIN Posts p ON c.PostId = p.Id
    GROUP BY
        c.PostId
    ORDER BY
        AvgCommentScore DESC
    LIMIT 10
),
BadgeUserAssociations AS (
    SELECT
        b.UserID,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS Badges
    FROM
        Badges b
    JOIN Users u ON b.UserId = u.Id
    GROUP BY
        b.UserId, u.DisplayName
)
SELECT
    tu.UserId,
    tu.DisplayName AS TopUser,
    tu.PostCount,
    at.Tags AS ActiveTag,
    at.TagCount,
    at.TotalViews,
    ca.postId,
    ca.AvgCommentScore,
    bua.BadgeCount,
    bua.Badges
FROM
    TopUsers tu
JOIN
    ActiveTags at ON 1=1
JOIN
    CommentsAnalysis ca ON 1=1
JOIN
    BadgeUserAssociations bua ON tu.UserId = bua.UserId
ORDER BY
    tu.PostCount DESC,
    at.TotalViews DESC,
    ca.AvgCommentScore DESC;
