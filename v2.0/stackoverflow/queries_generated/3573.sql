-- {"query": "3573.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2289} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentVotes AS (
    SELECT
        v.PostId,
        v.UserId,
        vt.Name AS VoteType,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TaggedPostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS rn
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    COALESCE(rv.VoteCount, 0) AS RecentVoteCount,
    CASE
        WHEN ua.TotalScore > 1000 THEN 'PowerUser'
        WHEN ua.TotalScore BETWEEN 500 AND 1000 THEN 'Experienced'
        ELSE 'Novice'
    END AS UserTier,
    STRING_AGG(DISTINCT tt.TagName, ', ') FILTER (WHERE tt.rn <= 5) AS TopFiveTags
FROM UserActivity ua
LEFT JOIN UserBadgeSummary ub ON ub.UserId = ua.UserId
LEFT JOIN (
    SELECT v.PostId, COUNT(*) AS VoteCount
    FROM RecentVotes v
    WHERE v.rn = 1
    GROUP BY v.PostId
) rv ON rv.PostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = ua.UserId
    ORDER BY p.CreationDate DESC
    LIMIT 1
)
LEFT JOIN (
    SELECT
        pt.UserId,
        t.TagName,
        t.rn
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) pt
    JOIN Tags t ON t.TagName = pt.Tag
) tt ON tt.UserId = ua.UserId
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    rv.VoteCount
HAVING ua.QuestionCount > 0

UNION ALL

SELECT
    NULL AS UserId,
    'Aggregate' AS DisplayName,
    SUM(ua.QuestionCount) AS QuestionCount,
    SUM(ua.AnswerCount) AS AnswerCount,
    SUM(ua.TotalScore) AS TotalScore,
    SUM(ub.GoldBadges) AS GoldBadges,
    SUM(ub.SilverBadges) AS SilverBadges,
    SUM(ub.BronzeBadges) AS BronzeBadges,
    SUM(rv.VoteCount) AS RecentVoteCount,
    NULL AS UserTier,
    NULL AS TopFiveTags
FROM UserActivity ua
LEFT JOIN UserBadgeSummary ub ON ub.UserId = ua.UserId
LEFT JOIN (
    SELECT v.PostId, COUNT(*) AS VoteCount
    FROM RecentVotes v
    WHERE v.rn = 1
    GROUP BY v.PostId
) rv ON rv.PostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = ua.UserId
    ORDER BY p.CreationDate DESC
    LIMIT 1
)
WHERE ua.QuestionCount > 0;
