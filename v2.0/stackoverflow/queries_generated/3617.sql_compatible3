WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
),
UserActivity AS (
    SELECT 
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views, 0)               AS Views,
        COALESCE(q.QuestionCount, 0)       AS QuestionCount,
        COALESCE(q.AnswerCount, 0)         AS AnswerCount,
        COALESCE(b.TotalBadges, 0)         AS TotalBadges,
        COALESCE(b.GoldBadges, 0)          AS GoldBadges,
        COALESCE(b.SilverBadges, 0)        AS SilverBadges,
        COALESCE(b.BronzeBadges, 0)        AS BronzeBadges,
        COALESCE(v.VoteUpCount, 0)         AS VoteUpCount,
        COALESCE(v.VoteDownCount, 0)       AS VoteDownCount,
        rp.LatestPostDate,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC)      AS RepRank,
        NTILE(4) OVER (ORDER BY u.Reputation DESC)          AS ReputationQuartile
    FROM Users u
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            COUNT(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE PostTypeId = 2) AS AnswerCount
        FROM Posts
        GROUP BY OwnerUserId
    ) q ON q.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            MAX(CreationDate) AS LatestPostDate
        FROM Posts
        GROUP BY OwnerUserId
    ) rp ON rp.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            b.UserId,
            COUNT(*)                                            AS TotalBadges,
            COUNT(*) FILTER (WHERE b.Class = 1)                 AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2)                 AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3)                 AS BronzeBadges,
            STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.TagBased = FALSE) AS NamedBadges
        FROM Badges b
        GROUP BY b.UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS VoteUpCount,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS VoteDownCount
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        JOIN Posts p ON p.Id = v.PostId
        GROUP BY p.OwnerUserId
    ) v ON v.OwnerUserId = u.Id
),
TagStats AS (
    SELECT 
        u.Id                                          AS UserId,
        COUNT(DISTINCT t.TagName)                     AS UniqueTagMentions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END),0) AS QuestionScoreSum,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END),0) AS AnswerScoreSum
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM COALESCE(p.Tags, '')), '><')) AS Tag
    ) tg ON p.Id IS NOT NULL
    LEFT JOIN Tags t ON t.TagName = tg.Tag
    GROUP BY u.Id
),
Combined AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Views,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalBadges,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.VoteUpCount,
        ua.VoteDownCount,
        ua.LatestPostDate,
        ua.RepRank,
        ua.ReputationQuartile,
        ts.UniqueTagMentions,
        ts.QuestionScoreSum,
        ts.AnswerScoreSum,
        CASE 
            WHEN ua.QuestionCount = 0 THEN NULL
            ELSE ROUND(COALESCE(ts.QuestionScoreSum,0) / NULLIF(ua.QuestionCount,0)::numeric, 2)
        END AS AvgQuestionScore,
        CASE 
            WHEN ua.AnswerCount = 0 THEN NULL
            ELSE ROUND(COALESCE(ts.AnswerScoreSum,0) / NULLIF(ua.AnswerCount,0)::numeric, 2)
        END AS AvgAnswerScore,
        (
            SELECT STRING_AGG(rp.Title, ' | ' ORDER BY rp.CreationDate DESC)
            FROM RecentPosts rp
            WHERE rp.OwnerUserId = ua.UserId AND rp.rn <= 3
        ) AS RecentTop3PostTitles
    FROM UserActivity ua
    LEFT JOIN TagStats ts ON ts.UserId = ua.UserId
),
TopUsers AS (
    SELECT *
    FROM Combined
    WHERE Reputation >= 10000
      AND TotalBadges >= 5
      AND (GoldBadges > 0 OR SilverBadges > 0)
    ORDER BY RepRank
    LIMIT 100
)
SELECT *
FROM (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        QuestionCount,
        AnswerCount,
        TotalBadges,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        VoteUpCount,
        VoteDownCount,
        LatestPostDate,
        RepRank,
        ReputationQuartile,
        UniqueTagMentions,
        QuestionScoreSum,
        AnswerScoreSum,
        AvgQuestionScore,
        AvgAnswerScore,
        RecentTop3PostTitles
    FROM TopUsers

    UNION ALL

    SELECT 
        CAST(NULL AS bigint)       AS UserId,
        '---'                     AS DisplayName,
        CAST(NULL AS int)         AS Reputation,
        CAST(NULL AS bigint)      AS Views,
        CAST(NULL AS int)         AS QuestionCount,
        CAST(NULL AS int)         AS AnswerCount,
        CAST(NULL AS int)         AS TotalBadges,
        CAST(NULL AS int)         AS GoldBadges,
        CAST(NULL AS int)         AS SilverBadges,
        CAST(NULL AS int)         AS BronzeBadges,
        CAST(NULL AS int)         AS VoteUpCount,
        CAST(NULL AS int)         AS VoteDownCount,
        CAST(NULL AS timestamp)   AS LatestPostDate,
        CAST(NULL AS int)         AS RepRank,
        CAST(NULL AS int)         AS ReputationQuartile,
        CAST(NULL AS int)         AS UniqueTagMentions,
        CAST(NULL AS int)         AS QuestionScoreSum,
        CAST(NULL AS int)         AS AnswerScoreSum,
        CAST(NULL AS numeric)     AS AvgQuestionScore,
        CAST(NULL AS numeric)     AS AvgAnswerScore,
        CAST(NULL AS text)        AS RecentTop3PostTitles
) t
ORDER BY RepRank NULLS LAST
LIMIT 101;