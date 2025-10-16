-- {"query": "22071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 718} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT COALESCE(t.TagName, ''), ', ') AS AllTags
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN unnest(string_to_array(COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ''), '><')) AS tag_array(tag) ON TRUE
    LEFT OUTER JOIN Tags t ON t.TagName = tag_array.tag
    WHERE u.Reputation > 1000 AND p.CreationDate IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
TopPostPerUser AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 0
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.PostCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgScore,
    ups.LastPostDate,
    ups.AllTags,
    bc.TotalBadges,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    tpp.Title AS TopPostTitle,
    tpp.Score AS TopPostScore,
    CASE 
        WHEN bc.GoldBadges > 0 THEN 'Elite'
        WHEN bc.SilverBadges > 1 THEN 'Advanced'
        ELSE 'Standard'
    END AS UserLevel,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = ups.UserId AND p2.PostTypeId = 1) 
     AND v.VoteTypeId = 2) AS TotalUpvotesOnQuestions,
    ups.Reputation / NULLIF(ups.PostCount, 0) AS ReputationPerPost,
    LENGTH(COALESCE(ups.AllTags, '')) AS TagStringLength
FROM UserPostStats ups
LEFT OUTER JOIN BadgeCounts bc ON ups.UserId = bc.UserId
LEFT OUTER JOIN TopPostPerUser tpp ON ups.UserId = tpp.OwnerUserId AND tpp.Rank = 1
WHERE ups.QuestionCount > 0 AND bc.TotalBadges IS NOT NULL
ORDER BY ups.Reputation DESC, ups.PostCount DESC
LIMIT 100;