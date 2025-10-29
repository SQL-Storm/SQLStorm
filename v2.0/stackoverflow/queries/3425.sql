WITH
    UserAgg AS (
        SELECT
            u.Id                                              AS UserId,
            COALESCE(u.DisplayName, '(anonymous)')            AS DisplayName,
            u.Reputation,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
            SUM(COALESCE(p.Score, 0))                          AS TotalScore,
            MAX(p.CreationDate)                               AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    BadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(*)                                               AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)          AS Gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)          AS Silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)          AS Bronze
        FROM Badges b
        GROUP BY b.UserId
    ),

    VoteAgg AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        GROUP BY v.PostId
    ),

    TagAgg AS (
        SELECT
            p.OwnerUserId,
            STRING_AGG(
                DISTINCT
                REPLACE(REPLACE(p.Tags, '><', ','), '<', ''),
                ',' ORDER BY REPLACE(REPLACE(p.Tags, '><', ','), '<', '')
            ) AS TagCSV
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    TopTag AS (
        SELECT
            t.TagName,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
        FROM Tags t
        WHERE t.IsModeratorOnly = FALSE
    ),

    MainResults AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        COALESCE(ba.BadgeCount, 0)                                     AS TotalBadges,
        COALESCE(ba.Gold, 0)                                           AS GoldBadges,
        COALESCE(vu.UpVotes, 0) - COALESCE(vd.DownVotes, 0)            AS NetVotes,
        ta.TagCSV,
        (
          SELECT MAX(ph.CreationDate)
          FROM PostHistory ph
          WHERE ph.PostId IN (
                    SELECT p2.Id
                    FROM Posts p2
                    WHERE p2.OwnerUserId = ua.UserId
                )
            AND ph.PostHistoryTypeId = 10
        )                                                               AS LastCloseDate,
        (SELECT tt.TagName FROM TopTag tt WHERE tt.rn = 1)              AS TopTagOverall
    FROM UserAgg ua
    LEFT JOIN BadgeAgg ba ON ba.UserId = ua.UserId
    LEFT JOIN TagAgg ta ON ta.OwnerUserId = ua.UserId
    LEFT JOIN VoteAgg vu ON vu.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = ua.UserId
            ORDER BY p.CreationDate DESC
            LIMIT 1
        )
    LEFT JOIN VoteAgg vd ON vd.PostId = vu.PostId
    WHERE ua.Reputation >= 2000
      AND (ua.QuestionCount + ua.AnswerCount) >= 5
      AND EXISTS (
            SELECT 1
            FROM Posts p3
            WHERE p3.OwnerUserId = ua.UserId
              AND p3.Score > 0
        )
    ORDER BY ua.Reputation DESC
    LIMIT 50
    )

SELECT * FROM MainResults

UNION ALL

SELECT
    CAST(NULL AS INTEGER)       AS UserId,
    CAST(NULL AS VARCHAR)       AS DisplayName,
    CAST(NULL AS INTEGER)       AS Reputation,
    CAST(NULL AS INTEGER)       AS QuestionCount,
    CAST(NULL AS INTEGER)       AS AnswerCount,
    CAST(NULL AS INTEGER)       AS TotalScore,
    CAST(NULL AS INTEGER)       AS TotalBadges,
    CAST(NULL AS INTEGER)       AS GoldBadges,
    CAST(NULL AS INTEGER)       AS NetVotes,
    CAST(NULL AS VARCHAR)       AS TagCSV,
    CAST(NULL AS TIMESTAMP)     AS LastCloseDate,
    CAST(NULL AS VARCHAR)       AS TopTagOverall;