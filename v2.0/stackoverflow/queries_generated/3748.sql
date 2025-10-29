-- {"query": "3748.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2133} 

WITH UserPosts AS (
    SELECT
        u.Id                                    AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score),0)                AS TotalScore,
        MAX(p.CreationDate)                     AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*)                                    AS BadgeTotal,
        COUNT(*) FILTER (WHERE b.Class = 1)         AS GoldBadges,
        MAX(b.Date)                                 AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT
        p.OwnerUserId                               AS PostOwnerId,
        v.VoteTypeId,
        COUNT(*)                                    AS VoteCount
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY p.OwnerUserId, v.VoteTypeId
),
TopTags AS (
    SELECT
        up.UserId,
        tg.TagName,
        SUM(p.Score)                                 AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY up.UserId ORDER BY SUM(p.Score) DESC) AS rn
    FROM UserPosts up
    JOIN Posts p ON p.OwnerUserId = up.UserId AND p.PostTypeId = 1
    LEFT JOIN LATERAL (
        SELECT trim(both '<>' FROM t) AS TagName
        FROM regexp_split_to_table(p.Tags, '><') AS t
    ) tg ON true
    WHERE p.Tags IS NOT NULL
    GROUP BY up.UserId, tg.TagName
)
SELECT
    u.Id,
    COALESCE(up.DisplayName, u.DisplayName)           AS DisplayName,
    u.Reputation,
    COALESCE(up.QuestionCount,0)                       AS Questions,
    COALESCE(up.AnswerCount,0)                         AS Answers,
    COALESCE(up.TotalScore,0)                          AS TotalScore,
    COALESCE(vs.VoteSum,0)                             AS TotalVotesReceived,
    COALESCE(b.BadgeTotal,0)                           AS BadgesEarned,
    COALESCE(b.GoldBadges,0)                           AS GoldBadges,
    CASE
        WHEN b.LastBadgeDate IS NULL THEN 'Never'
        ELSE to_char(b.LastBadgeDate,'YYYY-MM-DD')
    END                                                AS LastBadge,
    COALESCE(tt.TagName,'(none)')                      AS TopTag,
    COALESCE(tt.TagScore,0)                            AS TopTagScore,
    up.LastPostDate                                   AS LastActivity
FROM Users u
LEFT JOIN UserPosts up   ON up.UserId = u.Id
LEFT JOIN (
    SELECT PostOwnerId, SUM(VoteCount) AS VoteSum
    FROM UserVotes
    GROUP BY PostOwnerId
) vs                    ON vs.PostOwnerId = u.Id
LEFT JOIN UserBadges b  ON b.UserId = u.Id
LEFT JOIN (
    SELECT UserId, TagName, TagScore
    FROM TopTags
    WHERE rn = 1
) tt                    ON tt.UserId = u.Id
WHERE (u.Reputation > 1000 OR up.QuestionCount IS NOT NULL)
ORDER BY u.Reputation DESC
LIMIT 100
OFFSET 0

UNION ALL

SELECT
    NULL                                      AS Id,
    'Aggregate Summary'                       AS DisplayName,
    NULL                                      AS Reputation,
    SUM(COALESCE(up.QuestionCount,0))          AS Questions,
    SUM(COALESCE(up.AnswerCount,0))            AS Answers,
    SUM(COALESCE(up.TotalScore,0))             AS TotalScore,
    SUM(COALESCE(vs.VoteSum,0))                AS TotalVotesReceived,
    SUM(COALESCE(b.BadgeTotal,0))              AS BadgesEarned,
    SUM(COALESCE(b.GoldBadges,0))              AS GoldBadges,
    NULL                                      AS LastBadge,
    NULL                                      AS TopTag,
    NULL                                      AS TopTagScore,
    NULL                                      AS LastActivity
FROM Users u
LEFT JOIN UserPosts up   ON up.UserId = u.Id
LEFT JOIN (
    SELECT PostOwnerId, SUM(VoteCount) AS VoteSum
    FROM UserVotes
    GROUP BY PostOwnerId
) vs                    ON vs.PostOwnerId = u.Id
LEFT JOIN UserBadges b  ON b.UserId = u.Id
HAVING COUNT(u.Id) > 0;
