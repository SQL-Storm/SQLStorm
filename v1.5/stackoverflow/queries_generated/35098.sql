-- {"query": "35098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 665} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50 AND u.Reputation > 1000
    ORDER BY u.Reputation DESC
    LIMIT 50
),
AnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) AS AnswersCount,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(p.Score) AS TotalAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
QuestionStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) AS QuestionsCount,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.Score) AS MaxQuestionScore,
        SUM(p.Score) AS TotalQuestionScore
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
VoteStats AS (
    SELECT
        v.UserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.UserId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    qs.QuestionsCount,
    qs.AvgQuestionScore,
    qs.MaxQuestionScore,
    qs.TotalQuestionScore,
    ans.AnswersCount,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.TotalAnswerScore,
    vs.UpvotesCast,
    vs.DownvotesCast,
    vs.LastVoteDate,
    COALESCE(ans.AnswersCount,0)::float / NULLIF(COALESCE(qs.QuestionsCount,0),0) AS AnswersToQuestionsRatio
FROM TopUsers tu
LEFT JOIN AnswerStats ans ON ans.UserId = tu.UserId
LEFT JOIN QuestionStats qs ON qs.UserId = tu.UserId
LEFT JOIN VoteStats vs ON vs.UserId = tu.UserId
ORDER BY tu.Reputation DESC, tu.UserId;