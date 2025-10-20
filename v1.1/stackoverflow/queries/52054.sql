-- {"query": "52054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 898} 
WITH UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS NumQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS NumAnswers,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.AnswerCount) AS TotalAnswerCount,
        SUM(p.CommentCount) AS TotalCommentCount
    FROM Posts p
    WHERE p.CreationDate BETWEEN '2010-01-01' AND '2023-01-01'
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) > 5
),
UserVoteStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(v.Id) AS TotalVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS AcceptedAnswers
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE v.VoteTypeId IN (1,2,3) AND p.CreationDate BETWEEN '2010-01-01' AND '2023-01-01'
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    WHERE Date BETWEEN '2010-01-01' AND '2023-01-01'
    GROUP BY UserId
),
UserCommentStats AS (
    SELECT 
        UserId,
        COUNT(*) AS NumComments,
        SUM(Score) AS TotalCommentScore,
        AVG(Score) AS AvgCommentScore
    FROM Comments
    WHERE CreationDate BETWEEN '2010-01-01' AND '2023-01-01'
    GROUP BY UserId
),
UserHistoryStats AS (
    SELECT 
        ph.UserId,
        COUNT(*) AS NumEdits,
        COUNT(DISTINCT ph.PostId) AS NumPostsEdited
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,24) AND ph.CreationDate BETWEEN '2010-01-01' AND '2023-01-01'
    GROUP BY ph.UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    ups.NumQuestions,
    ups.NumAnswers,
    ups.TotalPostScore,
    uvs.UpVotes,
    uvs.DownVotes,
    uvs.AcceptedAnswers,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ucs.NumComments,
    ucs.TotalCommentScore,
    uhs.NumEdits,
    uhs.NumPostsEdited,
    ROW_NUMBER() OVER (ORDER BY (ups.TotalPostScore + uvs.UpVotes - uvs.DownVotes + ubs.GoldBadges*50 + ubs.SilverBadges*10 + ubs.BronzeBadges*5 + ucs.TotalCommentScore + uhs.NumEdits) DESC) AS EngagementRank
FROM Users u
JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserHistoryStats uhs ON u.Id = uhs.UserId
WHERE u.Reputation > 1000
  AND ups.NumQuestions > 10
  AND ups.NumAnswers > 50
  AND ubs.GoldBadges > 0
  AND u.LastAccessDate > '2022-01-01'
ORDER BY EngagementRank
LIMIT 100;