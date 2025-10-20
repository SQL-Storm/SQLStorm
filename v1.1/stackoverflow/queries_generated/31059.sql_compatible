WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 4 THEN 1 ELSE 0 END) AS OffensiveVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostCount,
        QuestionCount,
        AnswerCount,
        Upvotes - Downvotes AS NetVotes,
        AvgScore,
        GoldBadges + SilverBadges + BronzeBadges AS TotalBadges
    FROM UserPostStats
    ORDER BY PostCount DESC
    LIMIT 10
)

SELECT 
    tuv.DisplayName,
    tuv.PostCount,
    tuv.QuestionCount,
    tuv.AnswerCount,
    tuv.NetVotes,
    tuv.AvgScore,
    tuv.TotalBadges,
    STRING_AGG(DISTINCT p.Tags, ', ') AS TagsUsed
FROM TopUsers tuv
JOIN Posts p ON tuv.UserId = p.OwnerUserId
WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
GROUP BY tuv.UserId, tuv.DisplayName, tuv.PostCount, tuv.QuestionCount, tuv.AnswerCount, tuv.NetVotes, tuv.AvgScore, tuv.TotalBadges
ORDER BY tuv.NetVotes DESC;