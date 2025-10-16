-- {"query": "2061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 479} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(v2.VoteTypeId = 2) AS TotalUpVotesReceived,
        SUM(v2.VoteTypeId = 3) AS TotalDownVotesReceived,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS Rank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v2 ON p.Id = v2.PostId OR c.Id = v2.PostId
    GROUP BY
        u.Id, u.DisplayName
),
TopPosters AS (
    SELECT
        UserId,
        DisplayName,
        TotalPosts,
        TotalComments,
        TotalUpVotesReceived,
        TotalDownVotesReceived
    FROM
        UserActivity
    WHERE
        Rank = 1
),
CommentAnalysis AS (
    SELECT 
        p.OwnerUserId AS PostOwnerId,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(c.Id) AS TotalCommentsOnPosts
    FROM 
        Comments c
    INNER JOIN 
        Posts p ON c.PostId = p.Id
    GROUP BY 
        p.OwnerUserId
)
SELECT
    tp.DisplayName,
    tp.TotalPosts,
    tp.TotalComments,
    tp.TotalUpVotesReceived,
    tp.TotalDownVotesReceived,
    CASE 
        WHEN ca.AvgCommentScore IS NULL THEN 'No comments on posts'
        ELSE CONCAT('Average Comment Score: ', CAST(ca.AvgCommentScore AS VARCHAR(10)))
    END AS CommentInsights,
    CASE
        WHEN ca.TotalCommentsOnPosts > 100 THEN 'Highly Commented'
        WHEN ca.TotalCommentsOnPosts BETWEEN 50 AND 100 THEN 'Moderately Commented'
        ELSE 'Lightly Commented'
    END AS CommentInteractivity
FROM
    TopPosters tp
LEFT JOIN
    CommentAnalysis ca ON tp.UserId = ca.PostOwnerId
ORDER BY
    tp.TotalPosts DESC, tp.TotalUpVotesReceived DESC;
