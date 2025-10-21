-- {"query": "52089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 574} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
TagEngagement AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN pt.Name LIKE '%question%' THEN p.Id END) AS TaggedQuestionCount,
        SUM(t.Count) AS TagPopularity
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY u.Id
),
TopUsers AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgQuestionScore,
        us.AvgAnswerScore,
        us.CommentCount,
        us.BadgeCount,
        us.VoteCount,
        te.TaggedQuestionCount,
        te.TagPopularity,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS Rank
    FROM UserStats us
    JOIN TagEngagement te ON us.UserId = te.UserId
    WHERE us.Reputation > 1000
      AND us.QuestionCount > 10
      AND us.AnswerCount > 50
      AND te.TaggedQuestionCount > 5
)
SELECT 
    tu.UserId,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    ROUND(tu.AvgQuestionScore, 2) AS AvgQuestionScore,
    ROUND(tu.AvgAnswerScore, 2) AS AvgAnswerScore,
    tu.CommentCount,
    tu.BadgeCount,
    tu.VoteCount,
    tu.TaggedQuestionCount,
    tu.TagPopularity,
    tu.Rank
FROM TopUsers tu
WHERE tu.Rank <= 20
ORDER BY tu.Reputation DESC;