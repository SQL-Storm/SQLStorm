-- {"query": "4378.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1265} 

WITH RECURSIVE UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankByReputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> 'Community'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(c.CommentCount, 0) AS ActualCommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScoreForUser,
        AVG(CAST(v.VoteTypeId AS NUMERIC)) OVER (PARTITION BY p.Id) AS AverageVoteTypeForPost
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(Id) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, c.CommentCount
),
UserContribution AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        pe.PostId,
        pe.Title,
        pe.PostTypeId,
        pe.Score,
        pe.ViewCount,
        pe.ActualCommentCount,
        pe.RankByScoreForUser,
        pe.AverageVoteTypeForPost,
        CASE
            WHEN pe.AverageVoteTypeForPost BETWEEN 1.9 AND 2.1 THEN 'Upvoted' -- Approximation for typical upvote value
            WHEN pe.AverageVoteTypeForPost BETWEEN 2.9 AND 3.1 THEN 'Downvoted' -- Approximation for typical downvote value
            ELSE 'Neutral/Other'
        END AS VoteSentiment
    FROM UserActivity ua
    JOIN PostEngagement pe ON ua.UserId = pe.OwnerUserId
    WHERE ua.RankByReputation <= 1000 -- Consider top 1000 users by reputation
)
SELECT
    uc.UserId,
    uc.DisplayName,
    uc.Reputation,
    uc.PostCount,
    uc.QuestionCount,
    uc.AnswerCount,
    uc.PostId,
    uc.Title,
    pt.Name AS PostTypeName,
    uc.Score,
    uc.ViewCount,
    uc.ActualCommentCount,
    uc.RankByScoreForUser,
    uc.VoteSentiment,
    CASE
        WHEN uc.RankByScoreForUser <= 5 THEN 'TopPerformer'
        WHEN uc.RankByScoreForUser BETWEEN 6 AND 25 THEN 'HighPerformer'
        ELSE 'StandardPerformer'
    END AS PerformanceTier,
    CASE
        WHEN uc.ViewCount > (SELECT AVG(ViewCount) FROM Posts) * 2 THEN 'HighTraffic'
        WHEN uc.Score > (SELECT AVG(Score) FROM Posts) * 3 THEN 'HighlyRated'
        ELSE 'Standard'
    END AS PostSignificance,
    (SELECT COUNT(*) FROM Comments WHERE PostId = uc.PostId AND UserId = uc.UserId) AS UserCommentsOnOwnPost,
    (SELECT COUNT(*) FROM Votes WHERE PostId = uc.PostId AND UserId = uc.UserId AND VoteTypeId = 2) AS UserUpvotesOnOwnPost, -- VoteTypeId 2 is UpMod
    (SELECT SUM(ph.Comment) FROM PostHistory ph WHERE ph.PostId = uc.PostId AND ph.UserId = uc.UserId AND ph.PostHistoryTypeId IN (4, 6)) AS EditCommentsFromUser, -- Edits
    CASE WHEN uc.AverageVoteTypeForPost IS NULL THEN 'NoVotes' ELSE 'Voted' END AS VoteStatusIndicator,
    COALESCE(pht.PostHistoryCount, 0) AS TotalPostHistoryRevisions
FROM UserContribution uc
JOIN PostTypes pt ON uc.PostTypeId = pt.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS PostHistoryCount
    FROM PostHistory
    GROUP BY PostId
) pht ON uc.PostId = pht.PostId
WHERE uc.Reputation > 1000
AND uc.Score > 0
AND uc.PostCreationDate > '2023-01-01'
ORDER BY uc.Reputation DESC, uc.Score DESC, uc.PostCreationDate DESC
LIMIT 100;
