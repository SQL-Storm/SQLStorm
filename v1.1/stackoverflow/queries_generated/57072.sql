-- {"query": "57072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 868} 

WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        COUNT(DISTINCT q.Id) AS TotalQuestions,
        SUM(v.VoteTypeId = 2) AS TotalUpvotes,
        SUM(v.VoteTypeId = 3) AS TotalDownvotes
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN
        Votes v ON u.Id = v.UserId and (v.VoteTypeId = 2 OR v.VoteTypeId = 3 )
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
    ORDER BY
        u.Reputation DESC
    LIMIT 100
),
TopTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.ViewCount) AS AvgViewCount,
        SUM(p.Score) AS TotalScore
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY
        t.Id, t.TagName, t.Count
    ORDER BY
        TagCount DESC
    LIMIT 50
),
ActivePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        u.DisplayName AS OwnerDisplayName
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.LastActivityDate > NOW() - INTERVAL '30 days'
    ORDER BY
        p.LastActivityDate DESC
    LIMIT 1000
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalAnswers,
    tu.TotalQuestions,
    tu.TotalUpvotes,
    tu.TotalDownvotes,
    tt.TagId,
    tt.TagName,
    tt.TagCount,
    tt.PostsWithTag,
    tt.AvgViewCount,
    tt.TotalScore,
    ap.PostId,
    ap.PostTypeId,
    ap.CreationDate,
    ap.Score AS PostScore,
    ap.ViewCount AS PostViewCount,
    ap.AnswerCount,
    ap.CommentCount,
    ap.LastActivityDate,
    ap.OwnerDisplayName
FROM
    TopUsers tu
CROSS JOIN
    TopTags tt
LEFT JOIN
    ActivePosts ap ON ap.OwnerDisplayName = tu.DisplayName
ORDER BY
    tu.Reputation DESC,
    tt.TagCount DESC,
    ap.LastActivityDate DESC;
 