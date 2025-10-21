-- {"query": "15029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 642}
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScore,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserTagPriority
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN LATERAL (
        SELECT DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t ON TRUE
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
),
InterestingUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        TagName,
        PostCount,
        QuestionScore + AnswerScore AS TotalScore
    FROM UserTagStats
    WHERE UserTagPriority <= 3 
      AND TagRank <= 10
      AND (QuestionScore + AnswerScore) > 100
)
SELECT 
    iu.DisplayName,
    iu.TagName,
    iu.PostCount,
    iu.TotalScore,
    COALESCE(b.GoldBadgeCount, 0) AS GoldBadges,
    CASE 
        WHEN iu.TotalScore > 1000 THEN 'Elite'
        WHEN iu.TotalScore > 500 THEN 'Advanced'
        ELSE 'Intermediate'
    END AS UserLevel,
    ROUND(100.0 * iu.PostCount / (
        SELECT MAX(PostCount) 
        FROM InterestingUsers ui 
        WHERE ui.TagName = iu.TagName
    ), 2) AS RelativeContribution
FROM InterestingUsers iu
LEFT JOIN (
    SELECT 
        UserId, 
        COUNT(*) AS GoldBadgeCount
    FROM Badges 
    WHERE Class = 1
    GROUP BY UserId
) b ON iu.UserId = b.UserId
WHERE iu.PostCount > 10
ORDER BY TotalScore DESC, PostCount DESC
LIMIT 100;
