-- {"query": "3381.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2298}
WITH UserStats AS (
    SELECT
        u.Id                                    AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)   AS NetVotes,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
        SUM(COALESCE(p.Score,0))                         AS TotalPostScore,
        MAX(p.CreationDate)                              AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
),
UserBadgeAgg AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ')                AS Badges,
        SUM(CASE b.Class WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 1 END) AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
UserRecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotesCast,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesCast,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBountyStarted,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
QuestionClosure AS (
    SELECT
        ph.PostId,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate,
        MIN(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INTEGER) END) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11)
    GROUP BY ph.PostId
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalPostScore,
    COALESCE(uba.Badges, '')                AS BadgesList,
    COALESCE(uba.BadgeScore,0)              AS BadgeScore,
    COALESCE(urv.UpVotesCast,0)             AS UpVotesCast,
    COALESCE(urv.DownVotesCast,0)           AS DownVotesCast,
    COALESCE(urv.TotalBountyStarted,0)      AS TotalBountyStarted,
    uc.ClosedDate,
    uc.ReopenedDate,
    cr.Name                                 AS CloseReasonName,
    CASE
        WHEN uc.ReopenedDate IS NOT NULL THEN 'Reopened'
        WHEN uc.ClosedDate   IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END                                    AS QuestionStatus,
    tt.TagName                              AS TopTag,
    tt.rn                                   AS TopTagRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.UserId)               AS CommentCount,
    (SELECT COUNT(*) FROM Posts p2
        WHERE p2.OwnerUserId = us.UserId
          AND p2.PostTypeId = 2
          AND p2.Score > 0)                                                    AS PositiveAnswers,
    (SELECT STRING_AGG(DISTINCT CAST(pl.LinkTypeId AS VARCHAR), ',')
        FROM PostLinks pl
        JOIN Posts p3 ON p3.Id = pl.PostId
        WHERE p3.OwnerUserId = us.UserId)                                      AS LinkTypesUsed,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC)        AS UserRank
FROM UserStats us
LEFT JOIN UserBadgeAgg   uba ON uba.UserId = us.UserId
LEFT JOIN UserRecentVotes urv ON urv.UserId = us.UserId
LEFT JOIN QuestionClosure uc
       ON uc.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = us.UserId
              AND p.PostTypeId = 1
            ORDER BY p.CreationDate DESC
            LIMIT 1
          )
LEFT JOIN CloseReasonTypes cr ON cr.Id = uc.CloseReasonId
LEFT JOIN TopTags tt
       ON tt.rn = (
            SELECT CAST(FLOOR(RANDOM()*10)+1 AS INTEGER)
       )
WHERE us.Reputation > 1000
  AND (us.QuestionCount + us.AnswerCount) > 10
  AND (us.TotalPostScore IS NULL OR us.TotalPostScore > 0)
GROUP BY
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalPostScore,
    uba.Badges,
    uba.BadgeScore,
    urv.UpVotesCast,
    urv.DownVotesCast,
    urv.TotalBountyStarted,
    uc.ClosedDate,
    uc.ReopenedDate,
    cr.Name,
    tt.TagName,
    tt.rn
ORDER BY UserRank
LIMIT 100 OFFSET 0;