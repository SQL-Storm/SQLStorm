-- {"query": "55093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1446} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                                    AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)           AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)           AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)           AS BronzeBadges,
        COUNT(p.Id)                                            AS PostCount,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)           AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)           AS AnswerCount,
        AVG(p.Score)                                           AS AvgPostScore,
        MAX(p.CreationDate)                                    AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(*)                                    AS QuestionCount,
        AVG(p.Score)                                AS AvgScore,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes
    FROM Tags t
    JOIN Posts p 
      ON p.Tags LIKE '%'||'<'||t.TagName||'>%' 
     AND p.PostTypeId = 1                         -- only questions
    LEFT JOIN PostHistory ph 
      ON ph.PostId = p.Id 
     AND ph.PostHistoryTypeId = 10                -- close votes recorded in history
    GROUP BY t.TagName
    HAVING COUNT(*) > 100
),

TopUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, BadgeCount DESC) AS rn
    FROM UserStats
    WHERE Reputation > 10000
)

SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.BadgeCount,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionCount,
    tu.AnswerCount,
    ROUND(tu.AvgPostScore,2)       AS AvgPostScore,
    tu.LastPostDate,
    COALESCE(tp.TagName, 'N/A')    AS TopTag,
    COALESCE(tp.QuestionCount,0)   AS TopTagQuestionCount,
    COALESCE(ROUND(tp.AvgScore,2),0) AS TopTagAvgScore
FROM TopUsers tu
LEFT JOIN LATERAL (
    SELECT 
        tp.TagName,
        tp.QuestionCount,
        tp.AvgScore
    FROM TagPopularity tp
    ORDER BY tp.QuestionCount DESC
    LIMIT 1
) tp ON true
WHERE tu.rn <= 10
ORDER BY tu.rn;
