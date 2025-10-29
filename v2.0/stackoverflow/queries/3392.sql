-- {"query": "3392.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2384}
WITH
    TopUsers AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(b.Id) AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    UserPostStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
            SUM(p.Score) AS TotalScore,
            MAX(p.CreationDate) AS LastPostDate,
            MAX(p.LastActivityDate) AS LastActivityDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    TagPopularity AS (
        SELECT
            t.TagName,
            t.Count AS TagCount,
            COALESCE(t.ExcerptPostId, t.WikiPostId) AS RepresentativePostId,
            ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn
        FROM Tags t
    ),
    RecentVotes AS (
        SELECT
            v.PostId,
            SUM(
                CASE
                    WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1
                    ELSE 0
                END
            ) AS NetScore,
            COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteCount,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Votes v
        WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
        GROUP BY v.PostId
    ),
    PostWithLatestEdit AS (
        SELECT
            p.Id,
            p.Title,
            p.Tags,
            p.CreationDate,
            (
                SELECT MAX(ph.CreationDate)
                FROM PostHistory ph
                WHERE ph.PostId = p.Id
                  AND ph.PostHistoryTypeId IN (4,5,6)
            ) AS LastEditDate,
            COALESCE(rv.NetScore, 0) AS RecentNetScore
        FROM Posts p
        LEFT JOIN RecentVotes rv ON rv.PostId = p.Id
        WHERE p.PostTypeId = 1
    )

SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(up.QuestionCount, 0) AS QuestionsAsked,
    COALESCE(up.AnswerCount, 0) AS AnswersGiven,
    up.TotalScore,
    up.LastPostDate,
    up.LastActivityDate,
    t.TagName,
    t.TagCount,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastEditDate,
    p.RecentNetScore,
    CASE
        WHEN up.TotalScore IS NULL THEN 'NoPosts'
        WHEN up.TotalScore > 1000 THEN 'HighScorer'
        ELSE 'Normal'
    END AS ScoreCategory,
    ('User_' || u.Id || '_' || REPLACE(COALESCE(u.DisplayName, 'unknown'), ' ', '_')) AS UserKey,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.RecentNetScore DESC NULLS LAST) AS QuestionRankInUser
FROM TopUsers u
FULL OUTER JOIN UserPostStats up ON up.UserId = u.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM PostWithLatestEdit pw
    ORDER BY pw.RecentNetScore DESC
    LIMIT 1
) p ON TRUE
LEFT JOIN LATERAL (
    SELECT *
    FROM TagPopularity tp
    WHERE tp.rn = 1
    ORDER BY tp.TagCount DESC
    LIMIT 1
) t ON TRUE
WHERE (u.Reputation > 1000 OR up.AnswerCount > 10)

UNION ALL

SELECT
    NULL AS UserId,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionsAsked,
    NULL AS AnswersGiven,
    NULL AS TotalScore,
    NULL AS LastPostDate,
    NULL AS LastActivityDate,
    tg.TagName,
    tg.TagCount,
    NULL AS Title,
    NULL AS Tags,
    NULL AS CreationDate,
    NULL AS LastEditDate,
    NULL AS RecentNetScore,
    'TagOnly' AS ScoreCategory,
    NULL AS UserKey,
    NULL AS QuestionRankInUser
FROM TagPopularity tg
WHERE tg.rn <= 5

ORDER BY ScoreCategory DESC NULLS LAST, QuestionRankInUser ASC
LIMIT 100;