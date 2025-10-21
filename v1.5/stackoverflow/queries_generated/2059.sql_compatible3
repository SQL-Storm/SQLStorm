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
        t.TagName,
        COUNT(*) AS PostCount
    FROM (
        SELECT
            UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR CHAR_LENGTH(Tags) - 2), '><')) AS TagName
        FROM
            Posts
        WHERE
            PostTypeId = 1
    ) AS t
    GROUP BY
        t.TagName
),
HighRepUsers AS (
    SELECT
        Id AS UserId,
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
            PostId) AS tc ON p.Id = tc.PostId
    LEFT JOIN
        CommentsWithScore cws ON p.Id = cws.PostId
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        UserReputationCTE ur ON u.Id = ur.UserId
    WHERE
        p.PostTypeId = 1 AND
        p.AnswerCount > 2 AND
        (TIMESTAMP '2024-10-01 12:34:56') - p.CreationDate < INTERVAL '365' DAY
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
    TagPopularityCTE tp ON POSITION(tp.TagName IN fq.Title) > 0
WHERE
    tp.PostCount > 50 AND
    fq.TotalComments > 10
ORDER BY
    fq.TotalComments DESC,
    fq.MaxCommentScore DESC;