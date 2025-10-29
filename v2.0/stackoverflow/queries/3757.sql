WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Views, 0) AS UserViews,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
),
TagPopularity AS (
    SELECT t.TagName,
           COUNT(p.Id) AS QuestionCount,
           SUM(p.Score) AS TotalScore,
           ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p
           ON p.Tags IS NOT NULL
          AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
          AND p.PostTypeId = 1
    GROUP BY t.TagName
),
TopTags AS (
    SELECT TagName,
           QuestionCount,
           TotalScore
    FROM TagPopularity
    WHERE TagRank <= 5
),
UserActivity AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.PostCount,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           COALESCE(vs.TotalVotes, 0) AS TotalVotes,
           COALESCE(ac.AcceptedAnswers, 0) AS AcceptedAnswers,
           ROW_NUMBER() OVER (ORDER BY
                 (us.Reputation
                  + us.GoldBadges * 1000
                  + us.SilverBadges * 500
                  + us.BronzeBadges * 100) DESC) AS ReputationRank
    FROM UserStats us
    LEFT JOIN (
        SELECT p.OwnerUserId,
               COUNT(v.Id) AS TotalVotes
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId IN (2, 3)
        GROUP BY p.OwnerUserId
    ) vs ON vs.OwnerUserId = us.Id
    LEFT JOIN (
        SELECT a.OwnerUserId,
               COUNT(*) AS AcceptedAnswers
        FROM Posts a
        JOIN Posts q ON q.Id = a.ParentId
        WHERE a.PostTypeId = 2
          AND q.AcceptedAnswerId = a.Id
        GROUP BY a.OwnerUserId
    ) ac ON ac.OwnerUserId = us.Id
),
OverallStats AS (
    SELECT COUNT(*) AS TotalUsers,
           SUM(CASE WHEN Reputation > 10000 THEN 1 ELSE 0 END) AS HighRepUsers,
           AVG(Reputation) AS AvgReputation
    FROM Users
)
SELECT ua.Id,
       ua.DisplayName,
       ua.Reputation,
       ua.PostCount,
       ua.GoldBadges,
       ua.SilverBadges,
       ua.BronzeBadges,
       ua.TotalVotes,
       ua.AcceptedAnswers,
       ua.ReputationRank,
       COALESCE(t.TagName, 'N/A') AS TopTag,
       COALESCE(t.QuestionCount, 0) AS TagQuestionCount,
       COALESCE(t.TotalScore, 0) AS TagScore
FROM UserActivity ua
LEFT JOIN LATERAL (
    SELECT tt.TagName,
           tt.QuestionCount,
           tt.TotalScore
    FROM TopTags tt
    ORDER BY ABS(tt.TotalScore -
                 (SELECT AVG(p.Score)
                  FROM Posts p
                  WHERE p.OwnerUserId = ua.Id)) ASC
    LIMIT 1
) t ON TRUE
WHERE ua.ReputationRank <= 100

UNION ALL

SELECT CAST(NULL AS INTEGER)                         AS Id,
       CAST('OVERALL' AS VARCHAR(40))                AS DisplayName,
       CAST(FLOOR(os.AvgReputation) AS INTEGER)      AS Reputation,
       CAST(os.TotalUsers AS INTEGER)                AS PostCount,
       CAST(NULL AS INTEGER)                         AS GoldBadges,
       CAST(NULL AS INTEGER)                         AS SilverBadges,
       CAST(NULL AS INTEGER)                         AS BronzeBadges,
       CAST(NULL AS INTEGER)                         AS TotalVotes,
       CAST(os.HighRepUsers AS INTEGER)              AS AcceptedAnswers,
       CAST(NULL AS INTEGER)                         AS ReputationRank,
       CAST('SUMMARY' AS VARCHAR(40))                 AS TopTag,
       CAST(NULL AS INTEGER)                         AS TagQuestionCount,
       CAST(NULL AS INTEGER)                         AS TagScore
FROM OverallStats os
ORDER BY ReputationRank NULLS LAST, Reputation DESC;