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
    WHERE v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30 days'
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
),
LatestPostPerUser_Alt AS (
    SELECT p.OwnerUserId AS UserId, p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
      AND p.Id = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = p.OwnerUserId
        ORDER BY p2.CreationDate DESC
        LIMIT 1
      )
),
RecentVoteCounts AS (
    SELECT v.PostId, COUNT(*) AS VoteCount
    FROM RecentVotes v
    WHERE v.rn = 1
    GROUP BY v.PostId
),
UserTagsExpanded AS (
    SELECT
        pt.UserId,
        pt.Tag
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) pt
),
UserTopTags AS (
    SELECT
        ut.UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM UserTagsExpanded ut
    JOIN Tags t ON t.TagName = ut.Tag
    GROUP BY ut.UserId, t.TagName
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(rvc_outer.VoteCount, 0) AS RecentVoteCount,
    CASE
        WHEN ua.TotalScore > 1000 THEN 'PowerUser'
        WHEN ua.TotalScore BETWEEN 500 AND 1000 THEN 'Experienced'
        ELSE 'Novice'
    END AS UserTier,
    STRING_AGG(DISTINCT utt.TagName, ', ') FILTER (WHERE utt.rn <= 5) AS TopFiveTags
FROM UserActivity ua
LEFT JOIN UserBadgeSummary ub ON ub.UserId = ua.UserId
LEFT JOIN (
    SELECT lp.UserId, COALESCE(rvc.VoteCount, 0) AS VoteCount
    FROM (
        SELECT UserId, PostId FROM LatestPostPerUser_Alt
    ) lp
    LEFT JOIN RecentVoteCounts rvc ON rvc.PostId = lp.PostId
) rv ON rv.UserId = ua.UserId
LEFT JOIN UserTopTags utt ON utt.UserId = ua.UserId
LEFT JOIN RecentVoteCounts rvc_outer ON rvc_outer.PostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = ua.UserId
    ORDER BY p.CreationDate DESC
    LIMIT 1
)
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    rvc_outer.VoteCount
HAVING ua.QuestionCount > 0

UNION ALL

SELECT
    NULL AS UserId,
    'Aggregate' AS DisplayName,
    SUM(ua.QuestionCount) AS QuestionCount,
    SUM(ua.AnswerCount) AS AnswerCount,
    SUM(ua.TotalScore) AS TotalScore,
    SUM(COALESCE(ub.GoldBadges,0)) AS GoldBadges,
    SUM(COALESCE(ub.SilverBadges,0)) AS SilverBadges,
    SUM(COALESCE(ub.BronzeBadges,0)) AS BronzeBadges,
    SUM(COALESCE(rvc_outer.VoteCount,0)) AS RecentVoteCount,
    NULL AS UserTier,
    NULL AS TopFiveTags
FROM UserActivity ua
LEFT JOIN UserBadgeSummary ub ON ub.UserId = ua.UserId
LEFT JOIN (
    SELECT lp.UserId, COALESCE(rvc.VoteCount, 0) AS VoteCount
    FROM (
        SELECT UserId, PostId FROM LatestPostPerUser_Alt
    ) lp
    LEFT JOIN RecentVoteCounts rvc ON rvc.PostId = lp.PostId
) rv ON rv.UserId = ua.UserId
LEFT JOIN RecentVoteCounts rvc_outer ON rvc_outer.PostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = ua.UserId
    ORDER BY p.CreationDate DESC
    LIMIT 1
)
WHERE ua.QuestionCount > 0;