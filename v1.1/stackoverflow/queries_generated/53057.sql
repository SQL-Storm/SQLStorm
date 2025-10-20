-- {"query": "53057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 885} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId = v.UserId
    GROUP BY v.UserId
),
EditHistory AS (
    SELECT 
        ph.UserId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
),
TopTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        STRING_AGG(t.TagName, ', ') WITHIN GROUP (ORDER BY COUNT(*) DESC) AS TopTags
    FROM Posts p
    CROSS APPLY STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS tag_array
    JOIN Tags t ON t.TagName = ANY(tag_array)
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) > 0
),
Combined AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.AvgPostScore,
        ua.TotalViews,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(va.UpVotesReceived, 0) AS UpVotesReceived,
        COALESCE(va.DownVotesReceived, 0) AS DownVotesReceived,
        COALESCE(eh.EditCount, 0) AS EditCount,
        eh.LastEditDate,
        tt.TopTags
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    LEFT JOIN VoteAnalysis va ON ua.UserId = va.UserId
    LEFT JOIN EditHistory eh ON ua.UserId = eh.UserId
    LEFT JOIN TopTags tt ON ua.UserId = tt.UserId
)
SELECT 
    c.UserId,
    u.DisplayName,
    c.Reputation,
    c.QuestionsAsked,
    c.AnswersGiven,
    c.AvgPostScore,
    c.TotalViews,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.UpVotesReceived,
    c.DownVotesReceived,
    c.EditCount,
    c.LastEditDate,
    c.TopTags,
    RANK() OVER (ORDER BY c.Reputation DESC) AS ReputationRank,
    RANK() OVER (ORDER BY c.GoldBadges DESC) AS GoldBadgeRank
FROM Combined c
JOIN Users u ON c.UserId = u.Id
WHERE c.Reputation > 1000 AND c.GoldBadges >= 1
ORDER BY c.Reputation DESC, c.GoldBadges DESC
LIMIT 100;
