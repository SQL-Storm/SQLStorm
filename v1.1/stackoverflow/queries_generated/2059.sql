-- {"query": "2059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 541} 

WITH UserReputationCTE AS (
    SELECT
        u.Id AS UserId,
        SUM(v.BountyAmount) OVER (PARTITION BY u.Id) AS TotalBountyAmount
    FROM
        Users u
    LEFT JOIN
        Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (8, 9)
),
TagPopularityCTE AS (
    SELECT
        unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS TagName,
        COUNT(*) AS PostCount
    FROM
        Posts
    WHERE
        PostTypeId = 1
    GROUP BY
        TagName
),
HighRepUsers AS (
    SELECT
        UserId,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS RowNum
    FROM
        Users
    WHERE
        Reputation > 1000
),
CommentsWithScore AS (
    SELECT
        c.PostId,
        MAX(c.Score) AS MaxCommentScore
    FROM
        Comments c
    GROUP BY
        c.PostId
),
FinalQuery AS (
    SELECT DISTINCT
        p.Id AS PostId,
        p.Title,
        COALESCE(tc.TotalComments, 0) AS TotalComments,
        COALESCE(cws.MaxCommentScore, 0) AS MaxCommentScore,
        ur.TotalBountyAmount
    FROM
        Posts p
    LEFT JOIN
        (SELECT
            PostId,
            COUNT(*) AS TotalComments
         FROM
            Comments
         GROUP BY
            PostId) tc ON p.Id = tc.PostId
    LEFT JOIN
        CommentsWithScore cws ON p.Id = cws.PostId
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        UserReputationCTE ur ON u.Id = ur.UserId
    WHERE
        p.PostTypeId = 1 AND
        p.AnswerCount > 2 AND
        EXTRACT(DAY FROM CURRENT_TIMESTAMP - p.CreationDate) < 365
)
SELECT
    fq.PostId,
    fq.Title,
    fq.TotalComments,
    fq.MaxCommentScore,
    fq.TotalBountyAmount,
    tp.TagName,
    tp.PostCount
FROM
    FinalQuery fq
LEFT JOIN
    TagPopularityCTE tp ON position(tp.TagName in fq.Title) > 0
WHERE
    tp.PostCount > 50 AND
    fq.TotalComments > 10
ORDER BY
    fq.TotalComments DESC,
    fq.MaxCommentScore DESC;
