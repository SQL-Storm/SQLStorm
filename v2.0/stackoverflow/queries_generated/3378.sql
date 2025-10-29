-- {"query": "3378.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2644} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(b.GoldCnt, 0)   AS GoldBadges,
        COALESCE(b.SilverCnt, 0) AS SilverBadges,
        COALESCE(b.BronzeCnt, 0) AS BronzeBadges,
        COALESCE(p.QCnt, 0)      AS QuestionCount,
        COALESCE(p.ACnt, 0)      AS AnswerCount,
        COALESCE(p.AccAnsCnt, 0) AS AcceptedAnswerCount,
        COALESCE(v.UpCnt, 0)     AS UpVoteCount,
        COALESCE(v.DnCnt, 0)     AS DownVoteCount,
        CASE
            WHEN COALESCE(p.ACnt, 0) = 0 THEN NULL
            ELSE ROUND(100.0 * COALESCE(p.AccAnsCnt, 0) / p.ACnt, 2)
        END AS AcceptanceRate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QCnt,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS ACnt,
            SUM(CASE WHEN PostTypeId = 2 AND AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AccAnsCnt
        FROM Posts
        GROUP BY OwnerUserId
    ) p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpCnt,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DnCnt
        FROM Votes
        GROUP BY UserId
    ) v ON u.Id = v.UserId
),

RecentActivity AS (
    SELECT
        u.Id,
        GREATEST(
            COALESCE(MAX(p.LastActivityDate), TIMESTAMP '1970-01-01'),
            u.LastAccessDate
        ) AS LastActivity,
        COUNT(c.Id) FILTER (WHERE c.CreationDate > CURRENT_DATE - INTERVAL '30 days') AS RecentCommentCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),

TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        COALESCE(e.ExcerptLen, 0) AS ExcerptLen,
        COALESCE(w.WikiLen, 0)    AS WikiLen
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS ExcerptLen
        FROM Posts p
        WHERE p.Id = t.ExcerptPostId
    ) e ON true
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS WikiLen
        FROM Posts p
        WHERE p.Id = t.WikiPostId
    ) w ON true
    WHERE t.TagName IS NOT NULL
),

UserTopTags AS (
    SELECT
        pt.OwnerUserId,
        STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TagList
    FROM Posts pt
    JOIN LATERAL regexp_split_to_table(pt.Tags, '><') AS raw_tag ON true
    JOIN Tags t ON t.TagName = trim(both '<>' FROM raw_tag)
    WHERE pt.PostTypeId = 1
    GROUP BY pt.OwnerUserId
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.AcceptanceRate,
    us.UpVoteCount,
    us.DownVoteCount,
    us.RepRank,
    ra.LastActivity,
    ra.RecentCommentCount,
    CASE
        WHEN us.QuestionCount = 0 THEN NULL
        ELSE ROUND(us.Reputation::numeric / us.QuestionCount, 2)
    END AS RepPerQuestion,
    CASE WHEN us.AnswerCount = 0 THEN 'NoAnswers' ELSE 'HasAnswers' END AS AnswerFlag,
    ut.TagList AS TopTags
FROM UserStats us
LEFT JOIN RecentActivity ra ON us.Id = ra.Id
LEFT JOIN UserTopTags ut ON us.Id = ut.OwnerUserId
WHERE us.RepRank <= 1000
ORDER BY us.RepRank
LIMIT 500

UNION ALL

SELECT
    NULL AS Id,
    'Tag Summary' AS DisplayName,
    NULL AS Reputation,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS AcceptanceRate,
    NULL AS UpVoteCount,
    NULL AS DownVoteCount,
    NULL AS RepRank,
    NULL AS LastActivity,
    NULL AS RecentCommentCount,
    NULL AS RepPerQuestion,
    NULL AS AnswerFlag,
    tp.TagName || ': ' || tp.TagUseCount || ' uses (Excerpt=' ||
        tp.ExcerptLen || ', Wiki=' || tp.WikiLen || ')' AS TopTags
FROM TagPopularity tp
WHERE tp.TagUseCount > (SELECT AVG(TagUseCount) FROM TagPopularity)
ORDER BY tp.TagUseCount DESC
LIMIT 20;
