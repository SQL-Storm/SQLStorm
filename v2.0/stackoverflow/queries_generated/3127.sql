-- {"query": "3127.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2646} 

WITH RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                         AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                         AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                         AS BronzeBadges,
        COUNT(*) FILTER (WHERE b.TagBased = 1)                               AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT
        t.TagName,
        COUNT(*)                                 AS QuestionCount,
        AVG(p.Score)                             AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.DisplayName IS NOT NULL) AS TopContributors
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(*) > 1000
),
AnswerStats AS (
    SELECT
        q.Id                              AS QuestionId,
        COUNT(a.Id)                       AS AnswerCount,
        MAX(a.Score)                      AS TopAnswerScore,
        MIN(a.CreationDate)               AS FirstAnswerDate,
        MAX(a.CreationDate)               AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
UserActivity AS (
    SELECT
        u.Id                                          AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ubc.GoldBadges, 0)                    AS GoldBadges,
        COALESCE(ubc.SilverBadges, 0)                  AS SilverBadges,
        COALESCE(ubc.BronzeBadges, 0)                  AS BronzeBadges,
        COALESCE(ubc.TagBasedBadges, 0)                AS TagBasedBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id)                     AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2)   AS UpVoteGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3)   AS DownVoteGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                             AS ReputationRank,
        AVG(COALESCE(p.Score, 0)) OVER (PARTITION BY u.Id)                          AS AvgPostScore
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 5000
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.ReputationRank,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TagBasedBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.UpVoteGiven,
    ua.DownVoteGiven,
    ua.AvgPostScore,
    COALESCE(rp.Title, 'No recent post')                     AS RecentTitle,
    COALESCE(rp.Tags, '')                                    AS RecentTags,
    CASE
        WHEN rp.Tags LIKE '%<sql>%'
            THEN 'SQL tagged'
        ELSE 'Other'
    END                                                      AS TagCategory,
    tu.QuestionCount                                         AS TagQuestionCount,
    tu.AvgScore                                              AS TagAvgScore,
    tu.TopContributors,
    asw.AnswerCount                                          AS Q_AnswerCount,
    asw.TopAnswerScore,
    asw.FirstAnswerDate,
    asw.LastAnswerDate
FROM UserActivity ua
LEFT JOIN LATERAL (
    SELECT rp.Title, rp.Tags
    FROM RecentPosts rp
    WHERE rp.OwnerUserId = ua.UserId AND rp.rn = 1
) rp ON TRUE
LEFT JOIN LATERAL (
    SELECT *
    FROM AnswerStats asw
    WHERE asw.QuestionId = (
        SELECT q.Id
        FROM Posts q
        WHERE q.OwnerUserId = ua.UserId AND q.PostTypeId = 1
        ORDER BY q.CreationDate DESC
        LIMIT 1
    )
) asw ON TRUE
LEFT JOIN TagUsage tu
    ON tu.TagName = ANY (string_to_array(rp.Tags, '><'))
WHERE ua.ReputationRank <= 100
ORDER BY ua.Reputation DESC
LIMIT 100
UNION ALL
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL
LIMIT 0;
