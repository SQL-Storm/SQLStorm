-- {"query": "52027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 703} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.AnswerCount) AS TotalAnswersReceived,
        SUM(p.CommentCount) AS TotalCommentsReceived,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) -- Up and Down votes
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
TopUsers AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY (Reputation + TotalScore + TotalVotesReceived) DESC) AS Rank
    FROM UserStats
    WHERE TotalPosts > 0
),
PostDetails AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        EXTRACT(MONTH FROM p.CreationDate) AS Month
    FROM Posts p
)
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.TotalViews,
    tu.TotalAnswersReceived,
    tu.TotalCommentsReceived,
    tu.TotalCommentsMade,
    tu.TotalVotesReceived,
    tu.TotalBadges,
    tu.Rank,
    ROUND(tu.TotalScore * 1.0 / NULLIF(tu.TotalPosts, 0), 2) AS AvgScorePerPost,
    ROUND(tu.TotalVotesReceived * 1.0 / NULLIF(tu.TotalPosts, 0), 2) AS AvgVotesPerPost,
    COUNT(DISTINCT pd.PostTypeId) AS DistinctPostTypes,
    AVG(pd.Score) AS AvgPostScore,
    SUM(CASE WHEN pd.Year = 2023 AND pd.Month BETWEEN 1 AND 6 THEN 1 ELSE 0 END) AS Posts2023H1,
    SUM(CASE WHEN pd.Year = 2023 AND pd.Month BETWEEN 7 AND 12 THEN 1 ELSE 0 END) AS Posts2023H2
FROM TopUsers tu
LEFT JOIN PostDetails pd ON tu.Id = pd.OwnerUserId
WHERE tu.Rank <= 100
GROUP BY 
    tu.Id, tu.DisplayName, tu.Reputation, tu.TotalPosts, tu.QuestionCount, tu.AnswerCount, 
    tu.TotalScore, tu.TotalViews, tu.TotalAnswersReceived, tu.TotalCommentsReceived, 
    tu.TotalCommentsMade, tu.TotalVotesReceived, tu.TotalBadges, tu.Rank
ORDER BY tu.Rank;