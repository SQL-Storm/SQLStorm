WITH
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            u.LastAccessDate,
            COALESCE(p.QuestionCount, 0)   AS QuestionCount,
            COALESCE(p.AnswerCount, 0)     AS AnswerCount,
            COALESCE(b.TotalBadges, 0)     AS TotalBadges,
            COALESCE(b.GoldBadges, 0)      AS GoldBadges,
            COALESCE(b.SilverBadges, 0)    AS SilverBadges,
            COALESCE(b.BronzeBadges, 0)    AS BronzeBadges
        FROM Users u
        LEFT JOIN (
            SELECT
                OwnerUserId,
                SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
                SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
            FROM Posts
            GROUP BY OwnerUserId
        ) p ON u.Id = p.OwnerUserId
        LEFT JOIN (
            SELECT
                UserId,
                COUNT(*)                                          AS TotalBadges,
                SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END)        AS GoldBadges,
                SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END)        AS SilverBadges,
                SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END)        AS BronzeBadges
            FROM Badges
            GROUP BY UserId
        ) b ON u.Id = b.UserId
    ),
    TopActiveUsers AS (
        SELECT
            us.*,
            ROW_NUMBER() OVER (
                ORDER BY (us.QuestionCount + us.AnswerCount) DESC,
                         us.Reputation DESC
            ) AS ActivityRank
        FROM UserStats us
        WHERE us.Reputation > 1000
    ),
    UserTagAffinity AS (
        SELECT
            u.Id                                            AS UserId,
            t.TagName,
            COUNT(*)                                        AS TagUseCount,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
        FROM Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        -- For portability, split tags using a generic method: remove angle brackets and split by '><'
        -- emulate regexp_split_to_table by replacing with standard string functions is dialect-specific;
        -- here assume Tags formatted like '<tag1><tag2>' and use a recursive split for portability where supported.
        -- Fallback: treat the whole Tags string as single tag if splitting not supported.
        LEFT JOIN Tags t ON t.TagName = (
            CASE
                WHEN p.Tags IS NULL THEN NULL
                WHEN POSITION('><' IN p.Tags) = 0 THEN REPLACE(REPLACE(p.Tags, '<', ''), '>', '')
                ELSE NULL
            END
        )
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY u.Id, t.TagName
    ),
    RecentVotes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate)                         AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
        GROUP BY v.PostId
    ),
    PostScoreWithVotes AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            COALESCE(rv.UpVotes, 0) - COALESCE(rv.DownVotes, 0) AS NetVoteDelta,
            rv.LastVoteDate,
            p.OwnerUserId,
            p.CreationDate
        FROM Posts p
        LEFT JOIN RecentVotes rv ON p.Id = rv.PostId
        WHERE p.PostTypeId = 1
    ),
    ClosedDuplicateInfo AS (
        SELECT
            ph.PostId,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)   AS CloseReasonId,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Text END)      AS CloseDetailJson,
            MAX(CASE WHEN ph.PostHistoryTypeId = 3 THEN ph.CreationDate END) AS DuplicateDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10, 3)
        GROUP BY ph.PostId
    ),
    SelectedTopUsers AS (
        SELECT *
        FROM TopActiveUsers
        WHERE ActivityRank <= 50
    )
SELECT
    ta.Id                                 AS UserId,
    u.DisplayName,
    ta.Reputation,
    ta.QuestionCount,
    ta.AnswerCount,
    ta.TotalBadges,
    ta.GoldBadges,
    ta.SilverBadges,
    ta.BronzeBadges,
    COALESCE(uta.TagName, 'N/A')          AS TopTag,
    COALESCE(uta.TagUseCount, 0)          AS TopTagUseCount,
    ps.Title                              AS RecentQuestionTitle,
    ps.Score                              AS QuestionScore,
    ps.NetVoteDelta,
    COALESCE(cd.CloseReasonId, '0')       AS CloseReasonCode,
    CASE WHEN cd.CloseReasonId IS NOT NULL THEN 'Closed' ELSE 'Open' END AS ClosureStatus,
    CASE
        WHEN ps.LastVoteDate IS NULL THEN 0
        ELSE EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - ps.LastVoteDate))
    END                                  AS SecondsSinceLastVote,
    ta.ActivityRank
FROM SelectedTopUsers ta
JOIN Users u ON u.Id = ta.Id
LEFT JOIN UserTagAffinity uta ON uta.UserId = u.Id AND uta.TagRank = 1
LEFT JOIN LATERAL (
    SELECT *
    FROM PostScoreWithVotes
    WHERE OwnerUserId = u.Id
    ORDER BY CreationDate DESC
    LIMIT 1
) ps ON TRUE
LEFT JOIN ClosedDuplicateInfo cd ON cd.PostId = ps.Id

UNION ALL

SELECT
    NULL                                 AS UserId,
    'SUMMARY'                            AS DisplayName,
    NULL                                 AS Reputation,
    SUM(COALESCE(ta.QuestionCount, 0))   AS QuestionCount,
    SUM(COALESCE(ta.AnswerCount, 0))     AS AnswerCount,
    SUM(COALESCE(ta.TotalBadges, 0))     AS TotalBadges,
    SUM(COALESCE(ta.GoldBadges, 0))      AS GoldBadges,
    SUM(COALESCE(ta.SilverBadges, 0))    AS SilverBadges,
    SUM(COALESCE(ta.BronzeBadges, 0))    AS BronzeBadges,
    NULL                                 AS TopTag,
    NULL                                 AS TopTagUseCount,
    NULL                                 AS RecentQuestionTitle,
    NULL                                 AS QuestionScore,
    NULL                                 AS NetVoteDelta,
    NULL                                 AS CloseReasonCode,
    NULL                                 AS ClosureStatus,
    NULL                                 AS SecondsSinceLastVote,
    NULL                                 AS ActivityRank
FROM SelectedTopUsers ta

ORDER BY ActivityRank;