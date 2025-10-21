-- {"query": "52003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 585} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore,
    MAX(p.Score) AS MaxScore,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 35) THEN ph.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (11, 36) THEN ph.Id END) AS ReopenedQuestions,
    COUNT(DISTINCT pl.Id) AS PostLinksCount,
    SUM(CASE WHEN v2.VoteTypeId = 8 THEN v2.BountyAmount ELSE 0 END) AS TotalBountiesStarted,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion,
    COUNT(DISTINCT CASE WHEN c.Score > 10 THEN c.Id END) AS HighScoreComments,
    MAX(u.LastAccessDate) AS LastAccess,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND p.PostTypeId = 1
LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
LEFT JOIN Votes v2 ON u.Id = v2.UserId AND v2.VoteTypeId = 8
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE u.Reputation > 1000
GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
ORDER BY u.Reputation DESC
LIMIT 1000;