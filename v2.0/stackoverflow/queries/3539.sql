WITH RECURSIVE
UserStats AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views,0) + COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS ActivityScore,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    WHERE u.CreationDate < CAST('2024-10-01' AS date) - INTERVAL '1 year'
),

TopUsers AS (
    SELECT *
    FROM (
        SELECT us.*,
               ROW_NUMBER() OVER (ORDER BY us.ActivityScore DESC, us.Reputation DESC) AS rn
        FROM UserStats us
    ) t
    WHERE rn <= 100
),

BadgeCounts AS (
    SELECT UserId, 'Gold'   AS BadgeClass, GoldBadges   AS Cnt FROM TopUsers
    UNION ALL
    SELECT UserId, 'Silver' AS BadgeClass, SilverBadges AS Cnt FROM TopUsers
    UNION ALL
    SELECT UserId, 'Bronze' AS BadgeClass, BronzeBadges AS Cnt FROM TopUsers
),

TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                                            AS TagQuestionCount,
        SUM(COALESCE(p.Score,0))                               AS TagTotalScore,
        AVG(COALESCE(p.ViewCount,0))                           AS TagAvgViews,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Id IS NOT NULL) AS Contributors
    FROM Tags t
    LEFT JOIN Posts p
           ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN Users u
           ON u.Id = p.OwnerUserId
    WHERE t.IsModeratorOnly = FALSE
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
),

RecentVotes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1
                 WHEN vt.Id = 3 THEN -1
                 ELSE 0 END)                                 AS VoteBalance,
        MAX(v.CreationDate)                                 AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY v.PostId
),

ClosedDuplicatePosts AS (
    SELECT
        ph.PostId,
        CAST(MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS SMALLINT) AS CloseReasonCode,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END)       AS ClosedOn,
        -- aggregate texts into a concatenated string to avoid JSONB and grouping issues
        STRING_AGG(DISTINCT ph.Text, ' | ') FILTER (WHERE ph.PostHistoryTypeId = 10)   AS CloseVotesText
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),

PostView AS (
    SELECT
        p.Id                                      AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(rv.VoteBalance,0)                AS RecentVoteBalance,
        CASE p.PostTypeId
            WHEN 1 THEN 'Question'
            WHEN 2 THEN 'Answer'
            ELSE 'Other'
        END                                       AS PostCategory,
        COALESCE(cd.CloseReasonCode, 0)           AS CloseReasonCode,
        CASE WHEN cd.CloseReasonCode IS NOT NULL THEN 'Closed' ELSE 'Open' END AS Status,
        u.DisplayName                             AS OwnerName,
        u.Reputation,
        pt.TagName,
        ts.TagQuestionCount,
        ts.TagTotalScore,
        ts.TagAvgViews,
        ts.Contributors,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId
                           ORDER BY p.Score DESC NULLS LAST,
                                    p.CreationDate DESC) AS RankInCategory
    FROM Posts p
    LEFT JOIN Users u               ON u.Id = p.OwnerUserId
    LEFT JOIN RecentVotes rv        ON rv.PostId = p.Id
    LEFT JOIN ClosedDuplicatePosts cd ON cd.PostId = p.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName
    ) pt ON TRUE
    LEFT JOIN TagStats ts           ON ts.TagName = pt.TagName
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '180 days'
      AND (p.Score IS NULL OR p.Score > 0)
      AND (p.ViewCount IS NULL OR p.ViewCount > 10)
      AND (u.Reputation IS NULL OR u.Reputation > 100)
      AND (cd.CloseReasonCode IS NULL OR cd.CloseReasonCode <> 101)
),

CombinedResult AS (
    SELECT
        'Post'        AS RecordType,
        NULL          AS UserId,
        NULL          AS DisplayName,
        NULL          AS Reputation,
        p.PostId,
        p.Title,
        p.PostCategory,
        p.RankInCategory,
        p.Score,
        p.RecentVoteBalance,
        p.Status,
        p.CloseReasonCode,
        p.OwnerName,
        p.TagName,
        p.TagQuestionCount,
        p.TagTotalScore,
        p.TagAvgViews,
        p.Contributors,
        NULL          AS BadgeClass
    FROM PostView p
    WHERE p.RankInCategory <= 10

    UNION ALL

    SELECT
        'UserBadge'   AS RecordType,
        b.UserId,
        u.DisplayName,
        u.Reputation,
        NULL          AS PostId,
        NULL          AS Title,
        b.BadgeClass  AS PostCategory,
        NULL          AS RankInCategory,
        NULL          AS Score,
        NULL          AS RecentVoteBalance,
        NULL          AS Status,
        NULL          AS CloseReasonCode,
        NULL          AS OwnerName,
        NULL          AS TagName,
        NULL          AS TagQuestionCount,
        NULL          AS TagTotalScore,
        NULL          AS TagAvgViews,
        NULL          AS Contributors,
        b.BadgeClass  AS BadgeClass
    FROM BadgeCounts b
    JOIN Users u ON u.Id = b.UserId
)

SELECT *
FROM CombinedResult
ORDER BY RecordType,
         CASE WHEN RecordType = 'Post' THEN RankInCategory END,
         CASE WHEN RecordType = 'UserBadge' THEN BadgeClass END;