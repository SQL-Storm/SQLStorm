-- {"query": "11042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 979} 
WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS AuthorDisplayName, 
        u.Reputation AS AuthorReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT CASE WHEN c.UserId IS NOT NULL THEN c.UserId END) AS UniqueCommenters
    FROM 
        Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON p.Id = v.PostId
        LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopAuthors AS (
    SELECT 
        AuthorDisplayName, 
        SUM(Score) AS TotalScore, 
        SUM(ViewCount) AS TotalViews, 
        SUM(AnswerCount) AS TotalAnswers, 
        COUNT(Id) AS TotalPosts
    FROM 
        RecentPosts
    GROUP BY 
        AuthorDisplayName
    ORDER BY 
        TotalScore DESC, 
        TotalViews DESC, 
        TotalAnswers DESC, 
        TotalPosts DESC
    LIMIT 10
),
PostActivity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS AuthorDisplayName, 
        u.Reputation AS AuthorReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT CASE WHEN c.UserId IS NOT NULL THEN c.UserId END) AS UniqueCommenters
    FROM 
        Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON p.Id = v.PostId
        LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
PostRank AS (
    SELECT 
        Id, 
        Title, 
        CreationDate, 
        Score, 
        ViewCount, 
        AnswerCount, 
        AuthorDisplayName, 
        AuthorReputation, 
        VoteCount, 
        UpvoteCount, 
        DownvoteCount, 
        LastCommentDate, 
        UniqueCommenters,
        ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC, AnswerCount DESC) AS PostRank
    FROM 
        PostActivity
)
SELECT 
    pr.Id, 
    pr.Title, 
    pr.CreationDate, 
    pr.Score, 
    pr.ViewCount, 
    pr.AnswerCount, 
    pr.AuthorDisplayName, 
    pr.AuthorReputation, 
    pr.VoteCount, 
    pr.UpvoteCount, 
    pr.DownvoteCount, 
    pr.LastCommentDate, 
    pr.UniqueCommenters, 
    pr.PostRank, 
    ta.AuthorDisplayName AS TopAuthorDisplayName, 
    ta.TotalScore, 
    ta.TotalViews, 
    ta.TotalAnswers, 
    ta.TotalPosts
FROM 
    PostRank pr
    CROSS JOIN (
        SELECT 
            AuthorDisplayName, 
            TotalScore, 
            TotalViews, 
            TotalAnswers, 
            TotalPosts
        FROM 
            TopAuthors
        LIMIT 1
    ) ta
WHERE 
    pr.PostRank <= 10
ORDER BY 
    pr.PostRank;