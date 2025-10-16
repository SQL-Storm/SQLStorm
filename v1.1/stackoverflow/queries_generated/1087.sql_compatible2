WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p_count.views_count) AS AverageViews
    FROM 
        Users u
    LEFT JOIN 
        (SELECT 
            Id AS PostId, 
            OwnerUserId,
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
        -- Use a standard string aggregation function name that is supported in many dialects.
        -- Some DBs use STRING_AGG, LISTAGG, or GROUP_CONCAT; here we use STRING_AGG with CAST to varchar.
        STRING_AGG(CAST(v.UserId AS varchar), ', ') AS UserVotes
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
    TopVotedPosts p ON p.Rank = 1
WHERE 
    t.TotalPosts > 10 
    AND t.AverageViews > (SELECT AVG(AverageViews) FROM UserPostStats)
ORDER BY 
    t.TotalPosts DESC, p.VoteCount DESC;