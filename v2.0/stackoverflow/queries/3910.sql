WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVoteGiven
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

RankedUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.LastPostDate,
        us.BadgeCount,
        us.UpVoteGiven,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.BadgeCount DESC) AS RepRank,
        RANK()      OVER (ORDER BY us.TotalScore DESC)          AS ScoreRank
    FROM UserStats us
),

TagMentions AS (
    SELECT 
        t.TagName,
        COUNT(*)                               AS TagUsage,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS UsersUsingTag
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
    HAVING COUNT(*) > 1000
),

RecentClosed AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate)                                          AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)  AS CloseReasonJson
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),

Combined AS (
    SELECT 
        ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.TotalScore,
        ru.BadgeCount,
        ru.UpVoteGiven,
        rc.ClosedDate,
        rc.CloseReasonJson
    FROM RankedUsers ru
    LEFT JOIN RecentClosed rc ON rc.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ru.Id AND p.PostTypeId = 1
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
    WHERE ru.RepRank <= 100
),

-- helper to split display name into words in a cross-dialect way:
DisplayNameWords AS (
    SELECT 
        c.Id AS UserId,
        TRIM(w) AS word
    FROM Combined c,
    LATERAL (
        -- split on space characters; replace multiple spaces with single and then split
        SELECT regexp_split_to_table(regexp_replace(COALESCE(c.DisplayName, ''), '\s+', ' ', 'g'), ' ') AS w
    ) s
    WHERE COALESCE(c.DisplayName, '') <> ''
)

SELECT 
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.QuestionCount,
    c.AnswerCount,
    c.TotalScore,
    c.BadgeCount,
    c.UpVoteGiven,
    COALESCE(c.ClosedDate, TIMESTAMP '1970-01-01') AS LastClosedDate,
    COALESCE(c.CloseReasonJson, '{}')               AS CloseReason,
    tm.TagName,
    tm.TagUsage,
    tm.UsersUsingTag
FROM Combined c
LEFT JOIN LATERAL (
    SELECT t.TagName, t.TagUsage, t.UsersUsingTag
    FROM TagMentions t
    JOIN DisplayNameWords w ON w.UserId = c.Id
    WHERE LOWER(t.TagName) = LOWER(w.word)
    ORDER BY t.TagUsage DESC
    LIMIT 1
) tm ON TRUE

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0          AS QuestionCount,
    0          AS AnswerCount,
    0          AS TotalScore,
    b.BadgeCount,
    0          AS UpVoteGiven,
    NULL       AS ClosedDate,
    NULL       AS CloseReason,
    NULL       AS TagName,
    NULL       AS TagUsage,
    NULL       AS UsersUsingTag
FROM Users u
JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
    HAVING COUNT(*) > 50
) b ON b.UserId = u.Id
WHERE NOT EXISTS (SELECT 1 FROM Combined cc WHERE cc.Id = u.Id)

ORDER BY Reputation DESC, BadgeCount DESC
LIMIT 200;