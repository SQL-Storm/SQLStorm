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
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS Gold,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS Silver,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS Bronze,
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
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS ClosedQuestions
    FROM Posts p
    LEFT JOIN PostHistory ph 
        ON ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT 
        tag AS Tag,
        COUNT(*) AS QuestionCount,
        SUM(p.Score) AS ScoreSum
    FROM Posts p,
    LATERAL (
      SELECT TRIM(BOTH '<>' FROM SPLIT_PART(split_tag, '|', 1)) AS tag -- placeholder cleanup
      FROM (
        SELECT regexp_split_to_table(
               -- replace angle-bracket delimited tags like "<tag1><tag2>" with array elements
               regexp_replace(p.Tags, '^<|>$', '', 'g'),
               '><'
        ) AS split_tag
      ) s
    ) t
    WHERE p.PostTypeId = 1
    GROUP BY tag
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