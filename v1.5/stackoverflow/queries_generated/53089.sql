-- {"query": "53089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 926} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostHistoryStats AS (
    SELECT 
        ph.UserId,
        COUNT(ph.Id) AS TotalEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseReopenActions
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS QuestionCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserTagContributions AS (
    SELECT 
        ups.UserId,
        ts.TagId,
        COUNT(DISTINCT p.Id) AS PostsInTag,
        SUM(p.Score) AS ScoreInTag
    FROM UserPostStats ups
    JOIN Posts p ON ups.UserId = p.OwnerUserId
    CROSS JOIN TagStats ts
    WHERE p.Tags LIKE '%' || ts.TagName || '%'
    GROUP BY ups.UserId, ts.TagId
    HAVING COUNT(DISTINCT p.Id) > 5
)
SELECT 
    ups.UserId,
    ups.Reputation,
    ups.TotalPosts,
    ups.TotalScore,
    ups.AvgScore,
    ups.LastPostDate,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    vs.UpVotesGiven,
    vs.DownVotesGiven,
    cs.TotalComments,
    cs.AvgCommentScore,
    phs.TotalEdits,
    phs.CloseReopenActions,
    STRING_AGG(CONCAT(ts.TagName, ': ', utc.PostsInTag, ' posts, score ', utc.ScoreInTag), '; ') AS TagContributions
FROM UserPostStats ups
LEFT JOIN BadgeStats bs ON ups.UserId = bs.UserId
LEFT JOIN VoteStats vs ON ups.UserId = vs.UserId
LEFT JOIN CommentStats cs ON ups.UserId = cs.UserId
LEFT JOIN PostHistoryStats phs ON ups.UserId = phs.UserId
LEFT JOIN UserTagContributions utc ON ups.UserId = utc.UserId
LEFT JOIN TagStats ts ON utc.TagId = ts.TagId AND ts.TagRank <= 10
WHERE ups.Reputation > 10000
GROUP BY 
    ups.UserId, ups.Reputation, ups.TotalPosts, ups.TotalScore, ups.AvgScore, ups.LastPostDate,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
    vs.UpVotesGiven, vs.DownVotesGiven,
    cs.TotalComments, cs.AvgCommentScore,
    phs.TotalEdits, phs.CloseReopenActions
ORDER BY ups.TotalScore DESC
LIMIT 100;
