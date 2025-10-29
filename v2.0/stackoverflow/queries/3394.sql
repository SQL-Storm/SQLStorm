-- {"query": "3394.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2566}
WITH RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Title, '') AS Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),
UserActivity AS (
    SELECT
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ub.GoldBadges,   0)       AS GoldBadges,
        COALESCE(ub.SilverBadges, 0)       AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0)       AS BronzeBadges,
        COUNT(rp.Id) FILTER (WHERE rp.PostTypeId = 1) AS QuestionsPosted,
        COUNT(rp.Id) FILTER (WHERE rp.PostTypeId = 2) AS AnswersPosted,
        AVG(rp.Score) FILTER (WHERE rp.PostTypeId = 1) AS AvgQuestionScore,
        AVG(rp.Score) FILTER (WHERE rp.PostTypeId = 2) AS AvgAnswerScore,
        MAX(rp.CreationDate)               AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    LEFT JOIN RecentPosts rp     ON rp.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation,
             ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
TopUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.ReputationRank,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ROUND(CAST(ua.AvgQuestionScore AS numeric), 2) AS AvgQuestionScore,
        ROUND(CAST(ua.AvgAnswerScore AS numeric), 2)   AS AvgAnswerScore,
        ua.LastPostDate,
        CASE
            WHEN ua.Reputation > 20000                THEN 'Elite'
            WHEN ua.Reputation BETWEEN 10000 AND 19999 THEN 'Veteran'
            WHEN ua.Reputation BETWEEN 5000  AND 9999  THEN 'Experienced'
            ELSE 'Newbie'
        END AS ReputationTier,
        COALESCE(ts.TagName, 'NoTag')                AS SampleTag,
        ts.QuestionCount,
        ts.AnswerCount,
        ROUND(CAST(ts.AvgQuestionScore AS numeric), 2)                AS TagAvgQuestionScore,
        ROUND(CAST(ts.AvgAnswerScore AS numeric),   2)                AS TagAvgAnswerScore
    FROM UserActivity ua
    LEFT JOIN LATERAL (
        SELECT
            t.TagName,
            ts2.QuestionCount,
            ts2.AnswerCount,
            ts2.AvgQuestionScore,
            ts2.AvgAnswerScore
        FROM TagStats ts2
        JOIN Tags t ON t.TagName = ts2.TagName
        WHERE ua.UserId IN (
            SELECT OwnerUserId
            FROM Posts
            WHERE Tags LIKE '%' || t.TagName || '%'
              AND CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '90' DAY)
        )
        ORDER BY ts2.QuestionCount DESC
        LIMIT 1
    ) ts ON TRUE
    WHERE ua.ReputationRank <= 100
),
TopTags AS (
    SELECT
        CAST(NULL AS bigint)        AS UserId,
        '---'                       AS DisplayName,
        CAST(NULL AS integer)       AS Reputation,
        CAST(NULL AS integer)       AS ReputationRank,
        CAST(NULL AS integer)       AS GoldBadges,
        CAST(NULL AS integer)       AS SilverBadges,
        CAST(NULL AS integer)       AS BronzeBadges,
        CAST(NULL AS integer)       AS QuestionsPosted,
        CAST(NULL AS integer)       AS AnswersPosted,
        CAST(NULL AS numeric)       AS AvgQuestionScore,
        CAST(NULL AS numeric)       AS AvgAnswerScore,
        CAST(NULL AS timestamp)     AS LastPostDate,
        CAST(NULL AS text)          AS ReputationTier,
        tg.TagName                  AS SampleTag,
        tg.QuestionCount,
        tg.AnswerCount,
        tg.AvgQuestionScore,
        tg.AvgAnswerScore
    FROM TagStats tg
    WHERE tg.QuestionCount > 1000
    ORDER BY tg.QuestionCount DESC
    OFFSET 0 ROWS
    FETCH FIRST 10 ROWS ONLY
)
SELECT *
FROM (
    SELECT * FROM TopUsers
    UNION ALL
    SELECT * FROM TopTags
) combined
ORDER BY
    CASE WHEN Reputation IS NULL THEN 1 ELSE 0 END,
    Reputation DESC NULLS LAST,
    QuestionCount DESC NULLS LAST
LIMIT 50;