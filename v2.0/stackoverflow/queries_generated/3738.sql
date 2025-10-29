-- {"query": "3738.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2325} 

WITH
    /* Basic per‑user statistics */
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE( (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1), 0) AS GoldBadges,
            COALESCE( (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2), 0) AS SilverBadges,
            COALESCE( (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3), 0) AS BronzeBadges,
            COALESCE( (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 0) AS AvgQuestionScore,
            COALESCE( (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2), 0) AS AvgAnswerScore,
            (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
        FROM Users u
    ),

    /* Rank users by reputation and badge counts */
    RankedUsers AS (
        SELECT
            *,
            ROW_NUMBER() OVER (ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC) AS rn
        FROM UserStats
        WHERE Reputation > 10000
    ),

    /* Unnest tags for questions and count per user/tag */
    TagUsage AS (
        SELECT
            p.OwnerUserId AS UserId,
            UNNEST(
                string_to_array(
                    TRIM(BOTH '{}' FROM REPLACE(p.Tags, '><', ',')),
                    ','
                )
            ) AS Tag,
            COUNT(*) AS TagCount
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, Tag
    ),

    /* Rank tags per user */
    UserTagRank AS (
        SELECT
            tu.UserId,
            tu.Tag,
            tu.TagCount,
            RANK() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC) AS TagRank
        FROM TagUsage tu
    ),

    /* Most recent vote per post (last 30 days) */
    RecentVotes AS (
        SELECT
            v.PostId,
            v.VoteTypeId,
            v.CreationDate,
            v.UserId,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
        WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
    ),

    /* Question posts enriched with the latest vote info */
    QuestionWithVotes AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            p.CreationDate,
            COALESCE(rv.VoteTypeId, 0)          AS RecentVoteType,
            COALESCE(rv.CreationDate, p.CreationDate) AS RecentVoteDate
        FROM Posts p
        LEFT JOIN RecentVotes rv
               ON p.Id = rv.PostId AND rv.rn = 1
        WHERE p.PostTypeId = 1
    ),

    /* Combine user data with their latest question and top tag */
    Combined AS (
        SELECT
            ru.Id,
            ru.DisplayName,
            ru.Reputation,
            ru.GoldBadges,
            ru.SilverBadges,
            ru.BronzeBadges,
            ru.AvgQuestionScore,
            ru.AvgAnswerScore,
            ru.LastPostDate,
            COALESCE(q.Title, 'No recent question') AS RecentQuestionTitle,
            COALESCE(q.Score, 0)                 AS RecentQuestionScore,
            COALESCE(q.RecentVoteType, 0)        AS RecentVoteType,
            COALESCE(q.RecentVoteDate, ru.LastPostDate) AS RecentVoteDate,
            COALESCE(ut.Tag, 'None')             AS TopTag,
            COALESCE(ut.TagCount, 0)             AS TopTagCount
        FROM RankedUsers ru
        LEFT JOIN LATERAL (
            SELECT *
            FROM QuestionWithVotes qw
            WHERE qw.CreationDate = ru.LastPostDate
            LIMIT 1
        ) q ON TRUE
        LEFT JOIN LATERAL (
            SELECT Tag, TagCount
            FROM UserTagRank utr
            WHERE utr.UserId = ru.Id AND utr.TagRank = 1
        ) ut ON TRUE
        WHERE ru.rn <= 100
    )

SELECT *
FROM Combined
WHERE (Reputation IS NOT NULL AND Reputation > 0)
   OR (GoldBadges + SilverBadges + BronzeBadges) > 5
ORDER BY Reputation DESC, GoldBadges DESC
UNION ALL
SELECT
    Id,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AvgQuestionScore,
    AvgAnswerScore,
    LastPostDate,
    'No recent question' AS RecentQuestionTitle,
    0               AS RecentQuestionScore,
    0               AS RecentVoteType,
    LastPostDate    AS RecentVoteDate,
    'None'          AS TopTag,
    0               AS TopTagCount
FROM RankedUsers
WHERE rn > 100 AND rn <= 200
ORDER BY Reputation DESC
LIMIT 150;
