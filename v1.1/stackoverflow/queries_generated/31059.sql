-- {"query": "31059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 467} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(v.VoteTypeId = 2) AS Upvotes,
        SUM(v.VoteTypeId = 3) AS Downvotes,
        SUM(v.VoteTypeId = 4) AS OffensiveVotes,
        SUM(v.VoteTypeId = 5) AS Favorites,
        AVG(p.Score) AS AvgScore,
        SUM(b.Class = 1) AS GoldBadges,
        SUM(b.Class = 2) AS SilverBadges,
        SUM(b.Class = 3) AS BronzeBadges
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
WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY tuv.UserId, tuv.DisplayName, tuv.PostCount, tuv.QuestionCount, tuv.AnswerCount, tuv.NetVotes, tuv.AvgScore, tuv.TotalBadges
ORDER BY tuv.NetVotes DESC;
