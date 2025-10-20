-- {"query": "35016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 725} 
WITH HighRepUsers AS (
    SELECT Id AS UserId
    FROM Users
    WHERE Reputation > 10000
),
AnswererStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS AnswersCount,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AvgAnswerScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2 -- Answers
    GROUP BY u.Id
),
TopVotedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 100
      AND p.ViewCount > 10000
),
ActiveBadges AS (
    SELECT
        b.UserId,
        COUNT(*) AS RecentBadges
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY b.UserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        COUNT(*) AS TotalVotesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    a.AnswersCount,
    a.TotalAnswerScore,
    a.AvgAnswerScore,
    COALESCE(tbq.TopQuestions, 0) AS TopQuestions,
    COALESCE(ab.RecentBadges, 0) AS RecentBadges,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    COALESCE(ucs.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(uvs.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(uvs.DownvotesGiven, 0) AS DownvotesGiven,
    COALESCE(uvs.TotalVotesGiven, 0) AS TotalVotesGiven
FROM HighRepUsers hru
JOIN Users u ON u.Id = hru.UserId
LEFT JOIN AnswererStats a ON a.UserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS TopQuestions
    FROM TopVotedQuestions
    GROUP BY OwnerUserId
) tbq ON tbq.OwnerUserId = u.Id
LEFT JOIN ActiveBadges ab ON ab.UserId = u.Id
LEFT JOIN UserCommentStats ucs ON ucs.UserId = u.Id
LEFT JOIN UserVoteStats uvs ON uvs.UserId = u.Id
ORDER BY
    a.AvgAnswerScore DESC NULLS LAST,
    tbq.TopQuestions DESC NULLS LAST,
    ab.RecentBadges DESC NULLS LAST
LIMIT 50;