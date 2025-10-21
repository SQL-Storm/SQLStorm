-- {"query": "52075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 670} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY (TotalScore + (GoldBadges * 1000) + (TotalAnswers * 10)) DESC) AS Rank
    FROM UserStats
    WHERE GoldBadges > 0
),
PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01'
    GROUP BY p.Id, p.Title, p.Score, p.CreationDate, p.ViewCount, p.AnswerCount, pt.Name, u.DisplayName
),
TopPosts AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM CreationDate) ORDER BY Score DESC) AS YearRank
    FROM PostDetails
    WHERE Score > 50
)
SELECT 
    tu.Rank,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalQuestions,
    tu.TotalAnswers,
    tu.TotalScore,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.AvgPostScore,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.CreationDate,
    tp.ViewCount,
    tp.AnswerCount,
    tp.PostType,
    tp.OwnerDisplayName,
    tp.CommentCount,
    tp.NetVotes,
    tp.YearRank
FROM TopUsers tu
LEFT JOIN TopPosts tp ON tu.Id = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = tp.PostId LIMIT 1)
WHERE tu.Rank <= 10
ORDER BY tu.Rank, tp.Score DESC;