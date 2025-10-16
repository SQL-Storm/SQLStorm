-- {"query": "1087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 490} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(views_count) AS AverageViews
    FROM 
        Users u
    LEFT JOIN 
        (SELECT 
            PostId, 
            ViewCount AS views_count 
         FROM 
            Posts) p_count ON p_count.OwnerUserId = u.Id
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id
    GROUP BY 
        u.Id, u.DisplayName
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        AverageViews,
        RANK() OVER (ORDER BY TotalPosts DESC) AS Rank
    FROM 
        UserPostStats
),
MostVotedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COUNT(v.Id) AS VoteCount,
        STRING_AGG(v.UserId::text, ', ') AS UserVotes
    FROM 
        Posts p
    JOIN 
        Votes v ON v.PostId = p.Id
    GROUP BY 
        p.Id, p.Title
    HAVING 
        COUNT(v.Id) > 0
),
TopVotedPosts AS (
    SELECT 
        PostId,
        Title,
        VoteCount,
        UserVotes,
        RANK() OVER (ORDER BY VoteCount DESC) AS Rank
    FROM 
        MostVotedPosts
)
SELECT 
    t.UserId, 
    t.DisplayName, 
    t.TotalPosts, 
    t.TotalQuestions, 
    t.TotalAnswers, 
    t.AverageViews,
    p.Title AS TopVotedPostTitle,
    p.VoteCount,
    p.UserVotes
FROM 
    TopContributors t
LEFT JOIN 
    TopVotedPosts p ON t.Rank = 1
WHERE 
    t.TotalPosts > 10 
    AND t.AverageViews > (SELECT AVG(AverageViews) FROM UserPostStats)
ORDER BY 
    t.TotalPosts DESC, p.VoteCount DESC;
