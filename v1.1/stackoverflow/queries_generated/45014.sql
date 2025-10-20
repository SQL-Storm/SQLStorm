-- {"query": "45014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 32116, "output_tokens": 5541} 
WITH TopUsersByReputation AS (
    SELECT Id, Reputation, DisplayName,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) as ReputationRank
    FROM Users
    WHERE Reputation > 10000
),
PopularQuestionStats AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        ROUND(AVG(p.Score), 2) as AverageQuestionScore,
        MAX(p.ViewCount) as MaxViewCount
    FROM Posts p
    JOIN (SELECT Id, TagName FROM Tags) t ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    tur.Id as TopUserId,
    tur.DisplayName,
    tur.Reputation,
    pqs.TagName as MostPopularTag,
    pqs.QuestionCount,
    pqs.AverageQuestionScore,
    pqs.MaxViewCount
FROM TopUsersByReputation tur
CROSS JOIN PopularQuestionStats pqs
ORDER BY tur.Reputation DESC, pqs.QuestionCount DESC
LIMIT 50;