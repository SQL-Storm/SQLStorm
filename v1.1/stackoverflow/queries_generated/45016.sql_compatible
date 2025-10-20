WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        regexp_replace(p.Tags, '[><]', ' ', 'g') AS UserTags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank,
        COUNT(*) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, p.Tags
), 
ScoreSummary AS (
    SELECT 
        t.UserId, 
        t.DisplayName, 
        t.UserTags, 
        COUNT(*) OVER (PARTITION BY t.UserId) AS TotalQuestions,
        AVG(t.PostCount) OVER (PARTITION BY t.UserId) AS AvgQuestionScore,
        t.TagRank
    FROM TopUserTags t
    WHERE t.TagRank <= 3
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