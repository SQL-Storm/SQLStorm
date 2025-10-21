-- {"query": "53035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 911} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS Favorites
    FROM Votes v
    GROUP BY v.PostId
),
TagActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(p.Id) AS TagPostCount,
        SUM(p.Score) AS TagScore
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, TagName
    HAVING COUNT(p.Id) > 10
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    ua.QuestionCount,
    ua.AnswerCount,
    bs.BadgeCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    ta.TagName,
    ta.TagPostCount,
    ta.TagScore,
    ROW_NUMBER() OVER (PARTITION BY ta.TagName ORDER BY ta.TagScore DESC) AS TagRank,
    (SELECT AVG(vs.UpVotes - vs.DownVotes) FROM Posts p JOIN VoteSummary vs ON vs.PostId = p.Id WHERE p.OwnerUserId = ua.UserId) AS AvgNetVotes,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl JOIN Posts p ON p.Id = pl.PostId WHERE p.OwnerUserId = ua.UserId AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM UserActivity ua
JOIN BadgeStats bs ON bs.UserId = ua.UserId
JOIN TagActivity ta ON ta.UserId = ua.UserId
LEFT JOIN Posts p ON p.OwnerUserId = ua.UserId
LEFT JOIN EditHistory eh ON eh.PostId = p.Id
WHERE ua.Reputation > 10000
AND ua.TotalPosts > 50
GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalPosts, ua.TotalScore, ua.AvgScore, ua.LastPostDate, ua.QuestionCount, ua.AnswerCount, bs.BadgeCount, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, ta.TagName, ta.TagPostCount, ta.TagScore
HAVING AVG(eh.EditCount) > 1
ORDER BY ua.Reputation DESC, TagRank ASC
LIMIT 1000;
