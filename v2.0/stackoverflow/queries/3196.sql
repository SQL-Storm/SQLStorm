-- {"query": "3196.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2357}
WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation >= 20000
),
UserQuestions AS (
    SELECT
        p.Id               AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score           AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) AS q_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserBestAnswers AS (
    SELECT
        a.Id               AS AnswerId,
        a.ParentId         AS QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score            AS AnswerScore,
        ROW_NUMBER() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC, a.CreationDate ASC
        ) AS a_rank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
LatestPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ROW_NUMBER() OVER (
            PARTITION BY ph.PostId
            ORDER BY ph.CreationDate DESC
        ) AS h_rank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11,12,13)
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ')    AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
)

SELECT
    tu.Id                                    AS UserId,
    tu.DisplayName,
    tu.Reputation                           AS UserReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.BadgeList,
    q.QuestionId,
    q.Title,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    CASE
        WHEN q.Tags = '' THEN NULL
        ELSE regexp_split_to_array(q.Tags, '<|>')
    END                                      AS TagArray,
    a.AnswerId,
    a.AnswerScore,
    a.CreationDate                          AS AnswerDate,
    lh.PostHistoryTypeId,
    lh.Comment                               AS CloseReason,
    COALESCE(lh.Comment, 'No close reason') AS CloseInfo,
    ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY q.QuestionScore DESC) AS UserQuestionRank,
    ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY a.AnswerScore DESC NULLS LAST) AS UserAnswerRank
FROM TopUsers tu
LEFT JOIN UserQuestions q
       ON q.OwnerUserId = tu.Id AND q.q_rank = 1
LEFT JOIN UserBestAnswers a
       ON a.QuestionId = q.QuestionId AND a.a_rank = 1
LEFT JOIN LatestPostHistory lh
       ON lh.PostId = q.QuestionId AND lh.h_rank = 1
LEFT JOIN UserBadges ub
       ON ub.UserId = tu.Id
WHERE tu.rn <= 50

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation                           AS UserReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.BadgeList,
    CAST(NULL AS INTEGER) AS QuestionId,
    CAST(NULL AS TEXT)    AS Title,
    CAST(NULL AS INTEGER) AS QuestionScore,
    CAST(NULL AS INTEGER) AS ViewCount,
    CAST(NULL AS INTEGER) AS AnswerCount,
    CAST(NULL AS INTEGER) AS FavoriteCount,
    CAST(NULL AS TEXT[])  AS TagArray,
    CAST(NULL AS INTEGER) AS AnswerId,
    CAST(NULL AS INTEGER) AS AnswerScore,
    CAST(NULL AS TIMESTAMP) AS AnswerDate,
    CAST(NULL AS INTEGER) AS PostHistoryTypeId,
    CAST(NULL AS TEXT)    AS CloseReason,
    CAST(NULL AS TEXT)    AS CloseInfo,
    CAST(NULL AS INTEGER) AS UserQuestionRank,
    CAST(NULL AS INTEGER) AS UserAnswerRank
FROM Users u
LEFT JOIN UserBadges ub ON ub.UserId = u.Id
WHERE NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
      )
  AND u.Reputation BETWEEN 10000 AND 19999

ORDER BY UserReputation DESC, UserQuestionRank NULLS LAST
LIMIT 100;