-- {"query": "55049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1261} 
WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation > 10000
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
        COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
        COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) AS QuestionsAsked,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedQuestions
    FROM Posts p
    LEFT JOIN PostHistory ph 
        ON ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT 
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
        COUNT(*) AS QuestionCount,
        SUM(p.Score) AS ScoreSum
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY 1
    HAVING COUNT(*) > 1000
),
TopTags AS (
    SELECT 
        t.Tag,
        t.QuestionCount,
        t.ScoreSum,
        ROW_NUMBER() OVER (ORDER BY t.QuestionCount DESC) AS TagRank
    FROM TagPopularity t
)
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    ub.Gold,
    ub.Silver,
    ub.Bronze,
    qs.QuestionsAsked,
    qs.AvgQuestionScore,
    qs.TotalViews,
    qs.ClosedQuestions,
    ARRAY_AGG(tt.Tag ORDER BY tt.TagRank) FILTER (WHERE tt.TagRank <= 5) AS Top5Tags
FROM TopUsers tu
LEFT JOIN UserBadges ub      ON ub.UserId = tu.Id
LEFT JOIN QuestionStats qs   ON qs.UserId = tu.Id
LEFT JOIN TopTags tt         ON TRUE
WHERE tu.rn <= 50
GROUP BY 
    tu.Id, tu.DisplayName, tu.Reputation,
    ub.Gold, ub.Silver, ub.Bronze,
    qs.QuestionsAsked, qs.AvgQuestionScore, qs.TotalViews, qs.ClosedQuestions
ORDER BY 
    tu.Reputation DESC,
    ub.Gold DESC,
    qs.QuestionsAsked DESC
LIMIT 50;