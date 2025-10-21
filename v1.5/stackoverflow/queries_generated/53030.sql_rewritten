-- {"query": "53030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 763} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END) AS TotalScore,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE NULL END) AS AvgScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
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
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes v
    GROUP BY v.PostId
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Posts p
    INNER JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.AvgScore,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        SUM(vs.Upvotes) AS TotalUpvotes,
        SUM(vs.Downvotes) AS TotalDownvotes,
        pa.EditCount,
        pa.LastEditDate,
        ROW_NUMBER() OVER (ORDER BY bs.GoldBadges DESC, us.Reputation DESC) AS Rank
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT JOIN Posts p ON us.UserId = p.OwnerUserId
    LEFT JOIN VoteStats vs ON p.Id = vs.PostId
    LEFT JOIN PostActivity pa ON us.UserId = pa.OwnerUserId
    GROUP BY 
        us.UserId, us.Reputation, us.QuestionCount, us.AnswerCount, us.TotalScore, us.AvgScore,
        bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, pa.EditCount, pa.LastEditDate
)
SELECT 
    tu.UserId,
    u.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.AvgScore,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalUpvotes,
    tu.TotalDownvotes,
    tu.EditCount,
    tu.LastEditDate
FROM TopUsers tu
INNER JOIN Users u ON tu.UserId = u.Id
WHERE tu.Rank <= 100
ORDER BY tu.Rank;