-- {"query": "57057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 850} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(c.Id) AS TotalComments,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
HighActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        QuestionScore,
        AnswerScore,
        LastPostDate,
        TotalComments,
        TotalVotes,
        TotalUpvotes,
        TotalDownvotes
    FROM
        UserActivity
    WHERE
        TotalPosts > 100 AND
        TotalVotes > 500
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation
    FROM
        Tags t
    JOIN
        Posts p ON t.ExcerptPostId = p.Id
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        t.Count > 1000
    ORDER BY
        t.Count DESC
    LIMIT 50
)
SELECT
    ha.UserId,
    ha.Reputation,
    ha.UserCreationDate,
    ha.TotalPosts,
    ha.TotalQuestions,
    ha.TotalAnswers,
    ha.QuestionScore,
    ha.AnswerScore,
    ha.LastPostDate,
    ha.TotalComments,
    ha.TotalVotes,
    ha.TotalUpvotes,
    ha.TotalDownvotes,
    tt.TagName,
    tt.Title,
    tt.Score,
    tt.ViewCount,
    tt.AnswerCount,
    tt.OwnerDisplayName,
    tt.OwnerReputation
FROM
    HighActivityUsers ha
CROSS JOIN
    TopTags tt
ORDER BY
    ha.Reputation DESC,
    tt.Count DESC;
