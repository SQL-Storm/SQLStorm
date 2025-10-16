-- {"query": "22064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 932} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.Score) AS TotalVoteScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS Score
        FROM Votes
        WHERE VoteTypeId IN (2,3)
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE b.Class WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 1 END) AS BadgeScore,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date) AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TopUsers AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        COALESCE(ups.PostCount, 0) AS PostCount,
        COALESCE(ups.QuestionCount, 0) AS QuestionCount,
        COALESCE(ups.AnswerCount, 0) AS AnswerCount,
        ROUND(COALESCE(ups.AvgPostScore, 0), 2) AS AvgPostScore,
        COALESCE(ups.TotalVoteScore, 0) AS TotalVoteScore,
        COALESCE(ubs.BadgeCount, 0) AS BadgeCount,
        COALESCE(ubs.BadgeScore, 0) AS BadgeScore,
        ups.TotalVoteScore + ups.Reputation * 0.1 + ubs.BadgeScore AS CompositeScore,
        ROW_NUMBER() OVER (ORDER BY (ups.TotalVoteScore + ups.Reputation * 0.1 + ubs.BadgeScore) DESC) AS RankOverall,
        ubs.BadgeList
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
    WHERE ups.PostCount > 0 OR ubs.BadgeCount > 0
),
UserCommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    tu.*,
    COALESCE(uca.CommentCount, 0) AS CommentCount,
    ROUND(COALESCE(uca.AvgCommentLength, 0), 2) AS AvgCommentLength,
    CASE 
        WHEN tu.RankOverall <= 10 THEN 'Top 10'
        WHEN tu.RankOverall BETWEEN 11 AND 100 THEN 'Top 100'
        ELSE 'Others'
    END AS Category,
    CONCAT_WS(' - ', tu.DisplayName, 
        CASE WHEN tu.PostCount > 0 THEN CONCAT('Posts: ', tu.PostCount) ELSE NULL END,
        CASE WHEN tu.BadgeCount > 0 THEN CONCAT('Badges: ', tu.BadgeCount) ELSE NULL END
    ) AS UserSummary,
    EXISTS (
        SELECT 1 FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.AcceptedAnswerId IS NOT NULL
    ) AS HasAcceptedAnswer,
    tu.CompositeScore - (
        SELECT AVG(CompositeScore) 
        FROM TopUsers 
        WHERE RankOverall > tu.RankOverall
    ) AS ScoreAboveAverage,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = tu.UserId AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
FROM TopUsers tu
LEFT JOIN UserCommentActivity uca ON tu.UserId = uca.UserId
WHERE tu.CompositeScore > (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CompositeScore) FROM TopUsers
) OR tu.BadgeList IS NOT NULL
ORDER BY tu.RankOverall
LIMIT 100;