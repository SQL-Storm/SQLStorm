WITH 
UserPerf AS (
    SELECT 
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COUNT(p.Id)              AS PostCount,
        COALESCE(SUM(b.Class),0) AS BadgeClassSum,
        COUNT(DISTINCT b.Id)     AS BadgeCount,
        MAX(u.CreationDate)      AS FirstSeen,
        MIN(p.CreationDate)      AS FirstPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p           ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b          ON b.UserId = u.Id
    WHERE u.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserTagStats AS (
    SELECT 
        p.OwnerUserId               AS UserId,
        t.TagName,
        COUNT(*)                    AS QuestionsWithTag,
        SUM(p.Score)                AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM Posts p,
    LATERAL (
        SELECT TRIM(value) AS Tag
        FROM UNNEST(string_to_array(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), ',')) AS s(value)
    ) AS s
    LEFT JOIN Tags t ON t.TagName = s.Tag
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
RecentVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        COUNT(*)                AS VoteCount,
        MAX(v.CreationDate)     AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    GROUP BY v.PostId, v.VoteTypeId
),
ClosedQuestions AS (
    SELECT 
        p.Id               AS QuestionId,
        p.Title,
        p.OwnerUserId,
        ph.CreationDate    AS ClosedDate,
        CAST(ph.Comment AS INTEGER) AS CloseReasonId,
        cr.Name            AS CloseReasonName
    FROM Posts p
    LEFT JOIN PostHistory ph 
        ON ph.PostId = p.Id
       AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr 
        ON cr.Id = CAST(ph.Comment AS INTEGER)
    WHERE p.PostTypeId = 1
      AND ph.Id IS NOT NULL
),
TopContent AS (
    SELECT 
        p.Id                AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        u.Id                AS OwnerId,
        u.DisplayName,
        'Question'          AS ContentType,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT 
        p.Id,
        p.PostTypeId,
        NULL                AS Title,
        p.Score,
        u.Id,
        u.DisplayName,
        'Answer'            AS ContentType,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.TotalPostScore,
    up.PostCount,
    up.BadgeCount,
    up.BadgeClassSum,
    up.RepRank,
    COALESCE(uts.TagName, 'N/A')               AS TopTag,
    COALESCE(uts.QuestionsWithTag,0)           AS TagQuestionCount,
    COALESCE(uts.TagScore,0)                   AS TagScore,
    COALESCE(rv.VoteCount,0)                   AS RecentVoteCount,
    cq.QuestionId,
    cq.Title                                 AS ClosedQuestionTitle,
    cq.CloseReasonName,
    tc.PostId,
    tc.ContentType,
    tc.Score                                 AS ContentScore,
    tc.RankByScore
FROM UserPerf up
LEFT JOIN (
    SELECT *
    FROM UserTagStats
    WHERE TagRank = 1
) uts ON uts.UserId = up.UserId
LEFT JOIN RecentVotes rv 
    ON rv.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = up.UserId
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN ClosedQuestions cq 
    ON cq.OwnerUserId = up.UserId
LEFT JOIN (
    SELECT *
    FROM TopContent
    WHERE RankByScore <= 5
) tc ON tc.OwnerId = up.UserId
WHERE up.RepRank <= 1000
ORDER BY up.RepRank, tc.RankByScore DESC;