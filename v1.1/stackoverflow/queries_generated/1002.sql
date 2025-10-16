-- {"query": "1002.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 454} 

WITH UserMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(v.VoteTypeId IN (2), 0)) AS UpvoteCount,
        SUM(COALESCE(v.VoteTypeId IN (3), 0)) AS DownvoteCount,
        MAX(u.Reputation) AS Reputation
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        UpvoteCount,
        DownvoteCount,
        Reputation,
        RANK() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS UserRank
    FROM 
        UserMetrics
)
SELECT 
    u.DisplayName,
    u.UserRank,
    COALESCE(u.QuestionCount, 0) AS Questions,
    COALESCE(u.AnswerCount, 0) AS Answers,
    COALESCE(u.UpvoteCount, 0) AS Upvotes,
    u.Reputation,
    PS.closed_posts,
    PS.open_posts,
    PS.total_posts
FROM 
    RankedUsers u
LEFT JOIN (
    SELECT 
        OwnerUserId,
        COUNT(CASE WHEN ClosedDate IS NOT NULL THEN 1 END) AS closed_posts,
        COUNT(CASE WHEN ClosedDate IS NULL THEN 1 END) AS open_posts,
        COUNT(*) AS total_posts
    FROM 
        Posts
    GROUP BY 
        OwnerUserId
) PS ON u.UserId = PS.OwnerUserId
WHERE 
    u.UserRank <= 10
ORDER BY 
    u.UserRank;
