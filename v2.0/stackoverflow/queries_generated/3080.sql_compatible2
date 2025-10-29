WITH
UserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        CASE
            WHEN u.Reputation >= 20000 THEN 'Legendary'
            WHEN u.Reputation >= 10000 THEN 'Epic'
            WHEN u.Reputation >= 5000  THEN 'Veteran'
            WHEN u.Reputation >= 1000  THEN 'Experienced'
            ELSE 'Newbie'
        END AS RepTier
    FROM Users u
),
UserPosts AS (
    SELECT
        p.OwnerUserId            AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score)                           AS TotalScore,
        MAX(p.CreationDate)                    AS LastPostDate,
        STRING_AGG(p.Tags, ' ')                AS AllTags
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserTagRank AS (
    SELECT
        up.UserId,
        trim(both '<>' FROM raw.tag) AS Tag,
        ROW_NUMBER() OVER (PARTITION BY up.UserId ORDER BY t.cnt DESC) AS TagRank,
        t.cnt
    FROM UserPosts up
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(up.AllTags, '><')) AS tag
    ) raw
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM Posts p
        WHERE p.OwnerUserId = up.UserId
          AND p.Tags LIKE '%' || raw.tag || '%'
    ) t
    WHERE raw.tag <> ''
    GROUP BY up.UserId, raw.tag, t.cnt
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount,
        COUNT(*)                           AS TotalBadgeCount,
        STRING_AGG(DISTINCT b.Name, ',')   AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Id = 2) AS UpvoteCount,
        COUNT(*) FILTER (WHERE vt.Id = 3) AS DownvoteCount,
        SUM(CASE WHEN vt.Id = 2 THEN 1 WHEN vt.Id = 3 THEN -1 ELSE 0 END) AS VoteScore
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
Combined AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.RepTier,
        COALESCE(up.QuestionCount, 0)       AS QuestionCount,
        COALESCE(up.AnswerCount,   0)       AS AnswerCount,
        COALESCE(up.TotalScore,    0)       AS TotalScore,
        up.LastPostDate,
        COALESCE(ub.GoldBadgeCount,   0)    AS GoldBadges,
        COALESCE(ub.SilverBadgeCount, 0)    AS SilverBadges,
        COALESCE(ub.BronzeBadgeCount, 0)    AS BronzeBadges,
        COALESCE(vs.UpvoteCount,   0)       AS UpVotesGiven,
        COALESCE(vs.DownvoteCount, 0)       AS DownVotesGiven,
        COALESCE(vs.VoteScore,     0)       AS NetVoteScore,
        CASE
            WHEN up.LastPostDate IS NULL THEN NULL
            ELSE EXTRACT(day FROM (TIMESTAMP '2024-10-01 12:34:56' - up.LastPostDate))
        END                                 AS DaysSinceLastPost,
        COALESCE(ub.BadgeNames, '')         AS BadgeList
    FROM UserReputation u
    LEFT JOIN UserPosts    up ON up.UserId = u.Id
    LEFT JOIN UserBadges   ub ON ub.UserId = u.Id
    LEFT JOIN UserVotes    vs ON vs.UserId = u.Id
),
InactiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.RepTier,
        0 AS QuestionCount,
        0 AS AnswerCount,
        0 AS TotalScore,
        CAST(NULL AS TIMESTAMP) AS LastPostDate,
        0 AS GoldBadges,
        0 AS SilverBadges,
        0 AS BronzeBadges,
        0 AS UpVotesGiven,
        0 AS DownVotesGiven,
        0 AS NetVoteScore,
        CAST(NULL AS INTEGER) AS DaysSinceLastPost,
        '' AS BadgeList
    FROM UserReputation u
    WHERE NOT EXISTS (SELECT 1 FROM UserPosts up WHERE up.UserId = u.Id)
)
SELECT
    Id,
    DisplayName,
    RepTier,
    QuestionCount,
    AnswerCount,
    TotalScore,
    LastPostDate,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UpVotesGiven,
    DownVotesGiven,
    NetVoteScore,
    DaysSinceLastPost,
    BadgeList
FROM Combined
WHERE (QuestionCount + AnswerCount) > 0
   OR GoldBadges > 0
   OR UpVotesGiven > 100

UNION ALL

SELECT
    Id,
    DisplayName,
    RepTier,
    QuestionCount,
    AnswerCount,
    TotalScore,
    LastPostDate,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UpVotesGiven,
    DownVotesGiven,
    NetVoteScore,
    DaysSinceLastPost,
    BadgeList
FROM InactiveUsers

ORDER BY
    RepTier DESC,
    TotalScore DESC NULLS LAST,
    GoldBadges DESC,
    DaysSinceLastPost NULLS LAST;