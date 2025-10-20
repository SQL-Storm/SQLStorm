-- {"query": "43047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 655} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        MAX(u.LastAccessDate) AS LastActiveDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostFeedback AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId
),
CombinedMetrics AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.TotalScore,
        pf.PostId,
        pf.CommentCount,
        pf.VoteCount,
        pf.UpVotes,
        pf.DownVotes
    FROM UserActivity ua
    JOIN PostFeedback pf ON ua.UserId = pf.OwnerUserId
)
SELECT 
    cm.UserId,
    cm.DisplayName,
    cm.Reputation,
    cm.TotalPosts,
    cm.TotalQuestions,
    cm.TotalAnswers,
    cm.TotalScore,
    AVG(pf.CommentCount) AS AvgCommentsPerPost,
    AVG(pf.VoteCount) AS AvgVotesPerPost,
    AVG(pf.UpVotes) AS AvgUpVotesPerPost,
    AVG(pf.DownVotes) AS AvgDownVotesPerPost,
    RANK() OVER (ORDER BY cm.TotalScore DESC) AS UserRank
FROM CombinedMetrics cm
JOIN PostFeedback pf ON cm.PostId = pf.PostId
GROUP BY cm.UserId, cm.DisplayName, cm.Reputation, cm.TotalPosts, cm.TotalQuestions, cm.TotalAnswers, cm.TotalScore
ORDER BY UserRank;