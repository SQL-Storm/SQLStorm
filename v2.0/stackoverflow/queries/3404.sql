WITH UserBadgeCounts AS (
    SELECT u.Id AS UserId,
           SUM(CASE WHEN b.Class = 1 THEN 3 ELSE 1 END)                AS BadgeScore,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END)                      AS SilverCount,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END)                      AS BronzeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
UserPostStats AS (
    SELECT p.OwnerUserId                                            AS UserId,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)              AS QuestionCount,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)              AS AnswerCount,
           AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)          AS AvgQuestionScore,
           AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)          AS AvgAnswerScore,
           MAX(p.CreationDate)                                       AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserTagUsage AS (
    -- Split tag string like '<tag1><tag2>' into rows in a dialect-neutral way
    SELECT p.OwnerUserId                                           AS UserId,
           tag AS Tag,
           COUNT(*)                                                  AS TagUseCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT TRIM(t) AS tag
        FROM (
            SELECT
                -- generate positions of tags by splitting on '><'
                regexp_split_to_table(
                    -- remove leading '<' and trailing '>' if present
                    CASE
                        WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2)
                        ELSE p.Tags
                    END,
                    '><'
                ) AS t
        ) s
    ) split_tags
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
UserActivityScore AS (
    SELECT u.Id,
           COALESCE(up.QuestionCount,0) * 2 +
           COALESCE(up.AnswerCount,0) * 3 +
           COALESCE(ub.BadgeScore,0) * 5 +
           COALESCE(u.Reputation,0) / 1000.0                        AS BaseScore,
           COALESCE(up.LastPostDate, u.CreationDate)                AS RecentActivity,
           ROW_NUMBER() OVER (
               ORDER BY (COALESCE(up.QuestionCount,0) * 2 +
                         COALESCE(up.AnswerCount,0) * 3 +
                         COALESCE(ub.BadgeScore,0) * 5 +
                         COALESCE(u.Reputation,0) / 1000.0) DESC,
                        COALESCE(up.LastPostDate, u.CreationDate) DESC
           )                                                      AS Rank
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    LEFT JOIN UserPostStats up   ON up.UserId = u.Id
),
LatestEdit AS (
    SELECT ph.PostId,
           MAX(ph.CreationDate)                                        AS LastEditDate,
           (SELECT ph2.UserId
            FROM PostHistory ph2
            WHERE ph2.PostId = ph.PostId
              AND ph2.PostHistoryTypeId IN (4,5,6)
              AND ph2.CreationDate = MAX(ph.CreationDate)
            LIMIT 1)                                                   AS LastEditorUserId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
)
SELECT
    uas.Rank,
    u.Id                                 AS UserId,
    COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
    u.Reputation,
    uas.BaseScore,
    uas.RecentActivity,
    COALESCE(up.QuestionCount,0)          AS QuestionsAsked,
    COALESCE(up.AnswerCount,0)            AS AnswersGiven,
    COALESCE(ub.SilverCount,0)            AS SilverBadges,
    COALESCE(ub.BronzeCount,0)            AS BronzeBadges,
    STRING_AGG(DISTINCT tu.Tag || ':' || CAST(tu.TagUseCount AS varchar),
               ', ') FILTER (WHERE tu.TagUseCount > 5)                AS PopularTags,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Votes v
            JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
            WHERE v.UserId = u.Id
              AND vt.Name = 'UpMod'
              AND v.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days')
        ) THEN 'ActiveVoter'
        ELSE 'Quiet'
    END                                 AS RecentVotingBehavior,
    COALESCE(le.LastEditDate, p.CreationDate)                         AS LastActivityDate,
    COALESCE(le.LastEditorUserId, p.OwnerUserId)                       AS LastEditorId
FROM UserActivityScore uas
JOIN Users u               ON u.Id = uas.Id
LEFT JOIN UserPostStats up ON up.UserId = u.Id
LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
LEFT JOIN UserTagUsage tu  ON tu.UserId = u.Id
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
                 AND p.CreationDate = (
                     SELECT MAX(CreationDate)
                     FROM Posts
                     WHERE OwnerUserId = u.Id
                 )
LEFT JOIN LatestEdit le   ON le.PostId = p.Id
WHERE uas.Rank <= 10
GROUP BY
    uas.Rank, u.Id, u.DisplayName, u.Reputation, uas.BaseScore,
    uas.RecentActivity, up.QuestionCount, up.AnswerCount,
    ub.SilverCount, ub.BronzeCount,
    le.LastEditDate, p.CreationDate, le.LastEditorUserId, p.OwnerUserId
ORDER BY uas.Rank;