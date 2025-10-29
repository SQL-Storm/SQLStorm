-- {"query": "3287.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2340}
WITH
UserStats AS (
    SELECT
        u.Id                                          AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)       AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)       AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)       AS BronzeBadges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)  AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)  AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation,
        u.UpVotes, u.DownVotes
),

TopTagQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Id                               AS OwnerId,
        u.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC, p.CreationDate DESC) AS TagRank,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCnt,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)  AS UpVoteCnt,
        COALESCE(NULLIF(p.FavoriteCount,0),0) AS Favorites
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.Tags LIKE '%<sql>%'
      AND (p.Score * LOG(GREATEST(COALESCE(p.ViewCount,0),1)+1)) > 10
),

RecentActiveUsers AS (
    SELECT DISTINCT
        u.Id,
        u.DisplayName,
        MAX(p.CreationDate) OVER (PARTITION BY u.Id) AS LastPostDate,
        COUNT(p.Id)        OVER (PARTITION BY u.Id) AS PostsLastMonth
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
    WHERE u.CreationDate < CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.NetVotes,
    us.QuestionCount,
    us.AnswerCount,
    us.QuestionScoreSum,
    us.AnswerScoreSum,
    us.RepRank,
    tq.Id                AS TopQuestionId,
    tq.Title             AS TopQuestionTitle,
    tq.Score             AS TopQuestionScore,
    tq.ViewCount         AS TopQuestionViews,
    tq.AnswerCnt,
    tq.UpVoteCnt,
    tq.Favorites,
    CASE
        WHEN ra.LastPostDate IS NULL THEN 'Never Active'
        WHEN ra.LastPostDate >= CAST('2024-10-01' AS DATE) - INTERVAL '7' DAY THEN 'Hot'
        ELSE 'Dormant'
    END                AS ActivityStatus,
    COALESCE(ra.PostsLastMonth,0) AS PostsLast30Days
FROM UserStats us
LEFT JOIN (SELECT * FROM TopTagQuestions WHERE TagRank = 1) tq
    ON tq.OwnerId = us.UserId
LEFT JOIN RecentActiveUsers ra
    ON ra.Id = us.UserId
WHERE us.RepRank <= 1000
   OR us.GoldBadges > 0
   OR us.AnswerCount > 50

UNION ALL

SELECT
    NULL                AS UserId,
    'Aggregate Summary' AS DisplayName,
    NULL                AS Reputation,
    SUM(GoldBadges)   AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    NULL                AS NetVotes,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount)   AS AnswerCount,
    SUM(QuestionScoreSum) AS QuestionScoreSum,
    SUM(AnswerScoreSum)   AS AnswerScoreSum,
    NULL                AS RepRank,
    NULL                AS TopQuestionId,
    NULL                AS TopQuestionTitle,
    NULL                AS TopQuestionScore,
    NULL                AS TopQuestionViews,
    NULL                AS AnswerCnt,
    NULL                AS UpVoteCnt,
    NULL                AS Favorites,
    NULL                AS ActivityStatus,
    NULL                AS PostsLast30Days
FROM UserStats
WHERE RepRank <= 1000
ORDER BY RepRank ASC NULLS LAST, UserId ASC NULLS LAST;