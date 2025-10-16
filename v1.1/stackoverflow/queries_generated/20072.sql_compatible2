WITH UserAnswerStats AS (
    SELECT
        p_ans.OwnerUserId,
        COUNT(p_ans.Id) AS TotalAnswers,
        AVG(p_ans.Score) AS AverageAnswerScore,
        SUM(p_ans.CommentCount) AS TotalAnswerComments,
        AVG(EXTRACT(EPOCH FROM (p_ans.CreationDate - p_ques.CreationDate))) FILTER (WHERE p_ans.CreationDate > p_ques.CreationDate) AS AvgTimeToAnswerSeconds
    FROM Posts AS p_ans
    JOIN Posts AS p_ques ON p_ans.ParentId = p_ques.Id
    WHERE
        p_ans.PostTypeId = 2
        AND p_ques.PostTypeId = 1
        AND p_ans.OwnerUserId IS NOT NULL
    GROUP BY p_ans.OwnerUserId
    HAVING COUNT(p_ans.Id) >= 10
),
UserContributionDetails AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Location,
        uas.TotalAnswers,
        uas.AverageAnswerScore,
        uas.AvgTimeToAnswerSeconds,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.TagBased = 'false') AS GoldBadges,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.Tags,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalReputationRank,
        RANK() OVER (PARTITION BY SUBSTRING(u.Location FROM '^[^,]+') ORDER BY uas.AverageAnswerScore DESC, u.Reputation DESC) AS RankInLocationByScore,
        EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY u.Id ORDER BY p.CreationDate))) AS SecondsSinceLastPost
    FROM Users AS u
    JOIN UserAnswerStats AS uas ON u.Id = uas.OwnerUserId
    JOIN LATERAL (
        SELECT Id, CreationDate, Score, Tags
        FROM Posts
        WHERE OwnerUserId = u.Id
        ORDER BY CreationDate DESC
        LIMIT 5
    ) p ON TRUE
    WHERE u.Reputation > 5000 AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100
),
PrimaryContributors AS (
    SELECT
        ucd.UserId,
        ucd.DisplayName,
        ucd.Reputation,
        ucd.GlobalReputationRank,
        ucd.RankInLocationByScore,
        ucd.AverageAnswerScore,
        ucd.TotalAnswers,
        ucd.GoldBadges,
        ucd.Location,
        CASE
            WHEN ucd.Reputation > 150000 AND ucd.GoldBadges > 15 THEN 'Community Pillar'
            WHEN ucd.AvgTimeToAnswerSeconds < 3600 AND ucd.AverageAnswerScore > 5 THEN 'Swift Expert'
            WHEN ucd.AverageAnswerScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) * 2 THEN 'Quality Specialist'
            ELSE 'Dedicated Contributor'
        END AS UserCategory,
        'Contributor' AS ActivityType,
        (SELECT MAX(c.Score) FROM Comments c JOIN Posts p_c ON c.PostId = p_c.Id WHERE c.UserId = ucd.UserId AND p_c.OwnerUserId != ucd.UserId) AS MaxCommentScoreOnOthersPosts,
        ucd.SecondsSinceLastPost,
        ucd.AvgTimeToAnswerSeconds
    FROM UserContributionDetails ucd
    WHERE ucd.SecondsSinceLastPost IS NOT NULL AND ucd.SecondsSinceLastPost < (86400 * 90)
),
NicheQuestionAskers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        -1 AS GlobalReputationRank,
        -1 AS RankInLocationByScore,
        CAST(NULL AS numeric) AS AverageAnswerScore,
        (SELECT COUNT(*) FROM Posts p_ans WHERE p_ans.OwnerUserId = u.Id AND p_ans.PostTypeId = 2) AS TotalAnswers,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        u.Location,
        'Niche Inquisitor' AS UserCategory,
        'Asker' AS ActivityType,
        CAST(NULL AS integer) AS MaxCommentScoreOnOthersPosts
    FROM Users u
    WHERE u.Id IN (
        SELECT OwnerUserId
        FROM Posts
        WHERE PostTypeId = 1
          AND ViewCount > 50000
          AND AnswerCount <= 2
          AND (Tags LIKE '%<unusual-tag>%' OR Tags LIKE '%<specific-tech>%')
        GROUP BY OwnerUserId
        HAVING COUNT(Id) > 2
    )
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    GlobalReputationRank,
    RankInLocationByScore,
    COALESCE(AverageAnswerScore, 0) AS AverageAnswerScore,
    TotalAnswers,
    GoldBadges,
    UserCategory,
    ActivityType,
    REVERSE(SPLIT_PART(REVERSE(Location), ',', 1)) AS Country,
    MaxCommentScoreOnOthersPosts
FROM (
    SELECT UserId, DisplayName, Reputation, GlobalReputationRank, RankInLocationByScore, AverageAnswerScore, TotalAnswers, GoldBadges, Location, UserCategory, ActivityType, MaxCommentScoreOnOthersPosts FROM PrimaryContributors
    UNION ALL
    SELECT UserId, DisplayName, Reputation, GlobalReputationRank, RankInLocationByScore, AverageAnswerScore, TotalAnswers, GoldBadges, Location, UserCategory, ActivityType, MaxCommentScoreOnOthersPosts FROM NicheQuestionAskers
) AS CombinedUsers
WHERE
    (UserCategory = 'Community Pillar' OR Reputation > (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY Reputation) FROM Users))
    AND Location IS NOT NULL
    AND UserId IN (SELECT Id FROM Users WHERE CreationDate < CAST('2024-10-01' AS date) - INTERVAL '5 year')
ORDER BY
    UserCategory,
    GlobalReputationRank ASC,
    AverageAnswerScore DESC NULLS LAST;