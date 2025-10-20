-- {"query": "35049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 680} 
WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = a.Id OR v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT a.Id) > 10
    ORDER BY u.Reputation DESC
    LIMIT 50
),
UserActivity AS (
    SELECT
        u.UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate
    FROM TopUsers u
    LEFT JOIN Posts p ON (p.OwnerUserId = u.UserId)
    LEFT JOIN Comments c ON (c.UserId = u.UserId)
    GROUP BY u.UserId
),
UserBadges AS (
    SELECT
        u.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM TopUsers u
    LEFT JOIN Badges b ON (b.UserId = u.UserId)
    GROUP BY u.UserId
),
AnswerQuality AS (
    SELECT
        a.OwnerUserId,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END) AS HighScoringAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.UpVotesReceived,
    tu.DownVotesReceived,
    ua.CommentCount,
    ua.FirstPostDate,
    ua.LastPostDate,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    aq.AvgAnswerScore,
    aq.MaxAnswerScore,
    aq.HighScoringAnswers
FROM TopUsers tu
LEFT JOIN UserActivity ua ON tu.UserId = ua.UserId
LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
LEFT JOIN AnswerQuality aq ON tu.UserId = aq.OwnerUserId
ORDER BY tu.Reputation DESC, aq.AvgAnswerScore DESC NULLS LAST;