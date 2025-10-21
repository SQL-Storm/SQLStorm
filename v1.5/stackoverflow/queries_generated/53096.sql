-- {"query": "53096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 805} 

WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(CASE WHEN b.Class = 1 THEN 1 END) DESC) AS Rank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT *
    FROM UserBadgeCounts
    WHERE Rank <= 10
),
UserPosts AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsers)
    GROUP BY p.OwnerUserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes v
    WHERE v.UserId IN (SELECT UserId FROM TopUsers)
    GROUP BY v.UserId
),
UserComments AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IN (SELECT UserId FROM TopUsers)
    GROUP BY c.UserId
),
UserActivity AS (
    SELECT 
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,7,8,9) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.UserId IN (SELECT UserId FROM TopUsers)
    GROUP BY ph.UserId
),
UserTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        STRING_AGG(t.TagName, ', ') AS TopTags
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsers)
    AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT t.TagName) > 0
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    up.QuestionCount,
    up.AnswerCount,
    up.AvgPostScore,
    up.TotalViews,
    up.TotalFavorites,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uc.CommentCount,
    uc.AvgCommentScore,
    ua.EditCount,
    ua.LastEditDate,
    ut.TopTags
FROM TopUsers tu
LEFT JOIN UserPosts up ON tu.UserId = up.UserId
LEFT JOIN UserVotes uv ON tu.UserId = uv.UserId
LEFT JOIN UserComments uc ON tu.UserId = uc.UserId
LEFT JOIN UserActivity ua ON tu.UserId = ua.UserId
LEFT JOIN UserTags ut ON tu.UserId = ut.UserId
ORDER BY tu.Rank;
