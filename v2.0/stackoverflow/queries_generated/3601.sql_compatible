WITH
    UserPostAgg AS (
        SELECT
            u.Id AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    UserBadgeAgg AS (
        SELECT
            u.Id AS UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            STRING_AGG(
                CASE
                    WHEN b.Class = 1 AND b.Date >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
                    THEN b.Name
                    ELSE NULL
                END,
                ', '
            ) AS RecentGoldBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),
    UserRank AS (
        SELECT
            upa.*,
            DENSE_RANK() OVER (ORDER BY upa.Reputation DESC) AS ReputationRank
        FROM UserPostAgg upa
    ),
    TagStats AS (
        SELECT
            t.TagName,
            COUNT(p.Id) AS QuestionCount,
            AVG(p.ViewCount) AS AvgViews,
            SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalScore
        FROM Tags t
        LEFT JOIN Posts p
            ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
            AND p.PostTypeId = 1
        GROUP BY t.TagName
    ),
    UserTopTag AS (
        SELECT
            upa.UserId,
            (
                SELECT ts.TagName
                FROM TagStats ts
                JOIN Posts p ON p.Tags LIKE CONCAT('%<', ts.TagName, '>%')
                WHERE p.OwnerUserId = upa.UserId
                GROUP BY ts.TagName
                ORDER BY COUNT(*) DESC
                LIMIT 1
            ) AS TopTag
        FROM UserPostAgg upa
    ),
    CommentCountPerPost AS (
        SELECT
            p.Id AS PostId,
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
        FROM Posts p
    ),
    FinalResult AS (
        SELECT
            ur.UserId,
            ur.DisplayName,
            ur.Reputation,
            ur.ReputationRank,
            ur.QuestionCount,
            ur.AnswerCount,
            ROUND(ur.AvgQuestionScore, 2) AS AvgQuestionScore,
            ub.GoldBadges,
            ub.SilverBadges,
            ub.BronzeBadges,
            COALESCE(ub.RecentGoldBadges, '') AS RecentGoldBadges,
            ut.TopTag,
            COALESCE(ts.QuestionCount, 0) AS TopTagQuestionCount,
            COALESCE(ts.AvgViews, 0) AS TopTagAvgViews,
            COALESCE(cc.CommentCount, 0) AS LatestPostCommentCount
        FROM UserRank ur
        LEFT JOIN UserBadgeAgg ub ON ub.UserId = ur.UserId
        LEFT JOIN UserTopTag ut ON ut.UserId = ur.UserId
        LEFT JOIN TagStats ts ON ts.TagName = ut.TopTag
        LEFT JOIN LATERAL (
            SELECT cc.CommentCount
            FROM CommentCountPerPost cc
            WHERE cc.PostId = (
                SELECT p.Id
                FROM Posts p
                WHERE p.OwnerUserId = ur.UserId
                ORDER BY p.CreationDate DESC
                LIMIT 1
            )
        ) cc ON TRUE
        WHERE ur.Reputation > 10000
    )
SELECT *
FROM FinalResult

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    NULL AS ReputationRank,
    0 AS QuestionCount,
    0 AS AnswerCount,
    NULL AS AvgQuestionScore,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    '' AS RecentGoldBadges,
    '' AS TopTag,
    0 AS TopTagQuestionCount,
    0 AS TopTagAvgViews,
    0 AS LatestPostCommentCount
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id)

ORDER BY ReputationRank ASC NULLS LAST, UserId;