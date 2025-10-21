-- {"query": "45016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 393}
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        regexp_replace(p.Tags, '[><]', ' ', 'g') AS UserTags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, p.Tags
), 
ScoreSummary AS (
    SELECT 
        UserId, 
        DisplayName, 
        UserTags, 
        COUNT(*) OVER (PARTITION BY UserId) AS TotalQuestions,
        AVG(Score) OVER (PARTITION BY UserId) AS AvgQuestionScore
    FROM TopUserTags
    WHERE TagRank <= 3
)
SELECT 
    ss.UserId, 
    ss.DisplayName, 
    ss.UserTags,
    ss.TotalQuestions,
    ss.AvgQuestionScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ss.UserId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ss.UserId AND b.Class = 1) AS GoldBadges
FROM ScoreSummary ss
WHERE ss.TotalQuestions > 10
ORDER BY ss.AvgQuestionScore DESC, ss.TotalQuestions DESC
LIMIT 100;
