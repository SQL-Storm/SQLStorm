-- {"query": "13022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 745} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS TotalEdits,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    WHERE u.Reputation > 1000 AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    INNER JOIN Posts p ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '][')::int[])
    WHERE p.PostTypeId = 1 AND p.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.AvgPostScore,
    ua.TotalEdits,
    tt.TagName AS MostActiveTag,
    tt.PostCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1) AS HighestQuestionScore,
    CASE 
        WHEN ua.TotalEdits > 100 THEN 'Highly Active Editor'
        WHEN ua.TotalEdits BETWEEN 50 AND 100 THEN 'Moderately Active Editor'
        ELSE 'Low Activity Editor'
    END AS EditorActivityLevel
FROM UserActivity ua
CROSS JOIN LATERAL (
    SELECT t.TagName, t.PostCount
    FROM TopTags t
    WHERE EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '][')::text[]))
    ORDER BY t.PostCount DESC
    LIMIT 1
) tt
WHERE ua.LastActivityDate > CURRENT_DATE - INTERVAL '3 months'
ORDER BY ua.QuestionsAsked DESC, tt.PostCount DESC
LIMIT 50;
