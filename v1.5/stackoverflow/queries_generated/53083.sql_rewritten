-- {"query": "53083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 634} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
TagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.Id, t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 100
),
UserTagContributions AS (
    SELECT 
        tu.UserId,
        ts.TagId,
        COUNT(DISTINCT p.Id) AS AnswersInTag,
        ROW_NUMBER() OVER (PARTITION BY ts.TagId ORDER BY COUNT(DISTINCT p.Id) DESC) AS RankInTag
    FROM 
        TopUsers tu
    JOIN 
        Posts p ON tu.UserId = p.OwnerUserId AND p.PostTypeId = 2
    JOIN 
        Posts q ON p.ParentId = q.Id
    JOIN 
        TagStats ts ON q.Tags LIKE '%' || ts.TagName || '%'
    GROUP BY 
        tu.UserId, ts.TagId
)
SELECT 
    tu.UserId,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.AvgScore,
    tu.ReputationRank,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ts.TagName,
    ts.QuestionCount,
    ts.AvgQuestionScore,
    utc.AnswersInTag
FROM 
    TopUsers tu
LEFT JOIN 
    UserBadges ub ON tu.UserId = ub.UserId
LEFT JOIN 
    UserTagContributions utc ON tu.UserId = utc.UserId AND utc.RankInTag = 1
LEFT JOIN 
    TagStats ts ON utc.TagId = ts.TagId
WHERE 
    tu.ReputationRank <= 100
ORDER BY 
    tu.Reputation DESC, ts.QuestionCount DESC;