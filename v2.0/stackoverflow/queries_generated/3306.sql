-- {"query": "3306.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2191} 

WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
RecentVotes AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY v.PostId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        p.Id AS ExcerptPostId,
        COALESCE(p.FavoriteCount,0) AS ExcerptFavorites
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.IsModeratorOnly = 0
),
TopTags AS (
    SELECT
        TagName,
        TagUseCount,
        ROW_NUMBER() OVER (ORDER BY TagUseCount DESC) AS TagRank
    FROM TagPopularity
    WHERE TagUseCount IS NOT NULL
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ROUND(ups.AvgQuestionScore,2) AS AvgQScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    COALESCE(rv.NetRecentVotes,0) AS NetRecentVotes,
    CASE
        WHEN ub.TotalBadges >= 10 THEN 'Veteran'
        WHEN ub.TotalBadges BETWEEN 5 AND 9 THEN 'Experienced'
        ELSE 'Novice'
    END AS BadgeLevel,
    tt.TagName,
    tt.TagUseCount
FROM Users u
LEFT JOIN UserPostStats ups ON ups.UserId = u.Id
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        SUM(COALESCE(rv.UpVotes,0) - COALESCE(rv.DownVotes,0)) AS NetRecentVotes
    FROM Posts p
    LEFT JOIN RecentVotes rv ON rv.PostId = p.Id
    GROUP BY p.OwnerUserId
) rv ON rv.OwnerUserId = u.Id
LEFT JOIN LATERAL (
    SELECT
        t.TagName,
        t.TagUseCount
    FROM TopTags t
    WHERE t.TagRank <= 3
    ORDER BY t.TagUseCount DESC
    LIMIT 1
) tt ON TRUE
WHERE u.Reputation > 10000
  AND (ups.QuestionCount IS NULL OR ups.QuestionCount > 5)
  AND (ub.TotalBadges IS NULL OR ub.TotalBadges >= 1)
  AND (u.Location IS NOT NULL AND u.Location <> '')
ORDER BY u.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL,
    'Aggregate Summary',
    NULL,
    SUM(ups.QuestionCount)::int,
    SUM(ups.AnswerCount)::int,
    ROUND(AVG(ups.AvgQuestionScore),2),
    SUM(ub.GoldBadges),
    SUM(ub.SilverBadges),
    SUM(ub.BronzeBadges),
    SUM(ub.TotalBadges),
    NULL,
    NULL,
    NULL,
    NULL
FROM UserPostStats ups
JOIN UserBadgeStats ub ON ub.UserId = ups.UserId
WHERE EXISTS (
    SELECT 1 FROM Users u2 WHERE u2.Id = ups.UserId AND u2.Reputation > 10000
);
