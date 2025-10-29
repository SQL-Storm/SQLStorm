-- {"query": "3231.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2055} 

WITH UserPosts AS (
    SELECT u.Id AS UserId,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           COALESCE(SUM(p.Score),0)                 AS TotalScore,
           MAX(p.LastActivityDate)                  AS LastActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
UserBadges AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTags AS (
    SELECT p.OwnerUserId AS UserId,
           UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
           COUNT(*) AS TagFreq
    FROM Posts p
    WHERE p.PostTypeId = 1            -- only questions
    GROUP BY p.OwnerUserId, Tag
),
TopUserTag AS (
    SELECT ut.UserId,
           ut.Tag,
           ut.TagFreq,
           ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY ut.TagFreq DESC, ut.Tag) AS rn
    FROM UserTags ut
),
UserAnswerStats AS (
    SELECT q.OwnerUserId AS UserId,
           COUNT(a.Id)                                            AS AnswersToMyQuestions,
           AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL)       AS AvgAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.OwnerUserId
),
Combined AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(up.QuestionCount,0)                     AS QuestionCount,
           COALESCE(up.AnswerCount,0)                       AS AnswerCount,
           COALESCE(up.TotalScore,0)                        AS TotalScore,
           COALESCE(ub.GoldBadges,0)                        AS GoldBadges,
           COALESCE(ub.SilverBadges,0)                      AS SilverBadges,
           COALESCE(ub.BronzeBadges,0)                      AS BronzeBadges,
           COALESCE(t.Tag,'None')                           AS TopTag,
           COALESCE(t.TagFreq,0)                            AS TopTagUsage,
           COALESCE(a.AnswersToMyQuestions,0)               AS AnswersToMyQuestions,
           COALESCE(a.AvgAnswerScore,0)                     AS AvgAnswerScore,
           GREATEST(COALESCE(up.LastActivity, u.CreationDate), u.LastAccessDate) AS MostRecentActivity,
           (u.DisplayName || ' | Rep: ' || u.Reputation ||
            ' | Q: '   || COALESCE(up.QuestionCount,0) ||
            ' | A: '   || COALESCE(up.AnswerCount,0)   ||
            ' | Gold: '|| COALESCE(ub.GoldBadges,0))       AS Summary
    FROM Users u
    LEFT JOIN UserPosts up          ON up.UserId = u.Id
    LEFT JOIN UserBadges ub         ON ub.UserId = u.Id
    LEFT JOIN (SELECT UserId, Tag, TagFreq FROM TopUserTag WHERE rn = 1) t
                                    ON t.UserId = u.Id
    LEFT JOIN UserAnswerStats a    ON a.UserId = u.Id
)
SELECT *
FROM Combined
WHERE Reputation > 10000
   OR GoldBadges >= 5
   OR QuestionCount > 100

UNION ALL

SELECT Id,
       DisplayName,
       Reputation,
       QuestionCount,
       AnswerCount,
       TotalScore,
       GoldBadges,
       SilverBadges,
       BronzeBadges,
       TopTag,
       TopTagUsage,
       AnswersToMyQuestions,
       AvgAnswerScore,
       MostRecentActivity,
       Summary
FROM Combined
WHERE Reputation <= 10000
  AND GoldBadges = 0
  AND QuestionCount = 0

ORDER BY Reputation DESC NULLS LAST,
         GoldBadges DESC,
         QuestionCount DESC
LIMIT 100;
