WITH TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                                   AS QuestionCount,
        SUM(p.Score)                                  AS TotalScore,
        MAX(p.CreationDate)                           AS LatestQuestionDate
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
        AND p.PostTypeId = 1
    GROUP BY t.TagName
),

UserActivity AS (
    SELECT
        u.Id                                          AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        COUNT(DISTINCT p.Id)                          AS PostsAuthored,
        COUNT(DISTINCT c.Id)                          AS CommentsMade,
        MAX(p.CreationDate)                           AS LastPostDate,
        u.UpVotes,
        u.DownVotes
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TopGoldBadges AS (
    SELECT
        b.UserId,
        STRING_AGG(b.Name, ', ')                      AS GoldBadges,
        MAX(b.Date)                                   AS LatestGoldBadge
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),

RecentEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId
                           ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
),

UserLatestQuestion AS (
    SELECT
        u.Id                                            AS UserId,
        (SELECT p.Id
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.PostTypeId = 1
         ORDER BY p.CreationDate DESC
         LIMIT 1)                                       AS LatestQuestionId
    FROM Users u
)

SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.NetVotes,
    ua.PostsAuthored,
    ua.CommentsMade,
    COALESCE(tgb.GoldBadges, 'None')                    AS GoldBadges,
    COALESCE(tgb.LatestGoldBadge,
             CAST('1970-01-01 00:00:00' AS timestamp))  AS LatestGoldBadge,
    ts.TagName,
    ts.QuestionCount,
    ts.TotalScore,
    ts.LatestQuestionDate,
    CASE
        WHEN ts.TotalScore IS NULL           THEN 'No Questions'
        WHEN ts.TotalScore > 1000            THEN 'Hot Tag'
        ELSE                                 'Regular Tag'
    END                                                AS TagCategory,
    re.PostId                                          AS RecentlyEditedPostId,
    re.PostHistoryTypeId,
    re.CreationDate                                    AS EditDate,
    re.UserId                                          AS EditorUserId
FROM UserActivity ua
FULL OUTER JOIN TopGoldBadges tgb
    ON tgb.UserId = ua.UserId
LEFT JOIN UserLatestQuestion ulq
    ON ulq.UserId = ua.UserId
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(p.Tags, '><')) AS TagName,
           p.Id                                            AS PostId
    FROM Posts p
    WHERE p.Id = ulq.LatestQuestionId
) pt
    ON TRUE
LEFT JOIN TagStats ts
    ON ts.TagName = pt.TagName
LEFT JOIN RecentEdits re
    ON re.PostId = pt.PostId
   AND re.rn = 1
WHERE ua.Reputation > 1000
   OR tgb.GoldBadges IS NOT NULL
   OR ts.QuestionCount IS NOT NULL

UNION ALL

SELECT
    CAST(NULL AS bigint)                               AS UserId,
    CAST(NULL AS text)                                 AS DisplayName,
    CAST(NULL AS integer)                              AS Reputation,
    CAST(NULL AS integer)                              AS NetVotes,
    CAST(NULL AS integer)                              AS PostsAuthored,
    CAST(NULL AS integer)                              AS CommentsMade,
    CAST(NULL AS text)                                 AS GoldBadges,
    CAST(NULL AS timestamp)                            AS LatestGoldBadge,
    t.TagName,
    t.QuestionCount,
    t.TotalScore,
    t.LatestQuestionDate,
    'Tag Summary'                                     AS TagCategory,
    CAST(NULL AS bigint)                               AS RecentlyEditedPostId,
    CAST(NULL AS integer)                              AS PostHistoryTypeId,
    CAST(NULL AS timestamp)                            AS EditDate,
    CAST(NULL AS bigint)                               AS EditorUserId
FROM TagStats t
WHERE t.QuestionCount > 100
ORDER BY Reputation DESC NULLS LAST;