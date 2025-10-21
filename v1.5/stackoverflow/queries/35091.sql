-- {"query": "35091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 785} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50
), ActiveTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly
    FROM Tags t
    WHERE t.Count > 100
), UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
), QuestionScores AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Tags,
        p.Score,
        p.CreationDate,
        COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.Tags, p.Score, p.CreationDate
), TagDecompose AS (
    SELECT 
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName,
        q.Score,
        q.OwnerUserId,
        q.CreationDate,
        q.AnswerCount
    FROM QuestionScores q
), UserTagActivity AS (
    SELECT 
        t.TagName,
        q.OwnerUserId AS UserId,
        COUNT(*) AS QuestionCount,
        AVG(q.Score) AS AvgScore,
        SUM(q.AnswerCount) AS TotalAnswers
    FROM TagDecompose t
    JOIN QuestionScores q ON t.QuestionId = q.QuestionId
    GROUP BY t.TagName, q.OwnerUserId
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    at.TagName AS MostActiveTag,
    uta.QuestionCount AS QuestionsWithTag,
    uta.AvgScore AS AvgScoreWithTag,
    uta.TotalAnswers AS AnswersToTag,
    at.Count AS TagTotalUsage,
    at.IsRequired,
    at.IsModeratorOnly
FROM TopUsers tu
LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
LEFT JOIN LATERAL (
    SELECT 
        uta.TagName, 
        uta.QuestionCount, 
        uta.AvgScore, 
        uta.TotalAnswers
    FROM UserTagActivity uta
    JOIN ActiveTags at2 ON uta.TagName = at2.TagName
    WHERE uta.UserId = tu.UserId
    ORDER BY uta.QuestionCount DESC, uta.AvgScore DESC
    LIMIT 1
) uta ON TRUE
LEFT JOIN ActiveTags at ON uta.TagName = at.TagName
ORDER BY tu.Reputation DESC, tu.TotalPosts DESC
LIMIT 100;