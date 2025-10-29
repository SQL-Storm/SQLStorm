-- {"query": "3257.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2141} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.CreationDate, TIMESTAMP '1970-01-01') AS UserCreated,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)               AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)              AS QuestionScoreSum,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)              AS AnswerScoreSum,
        COUNT(b.Id)                                              AS BadgeCount,
        MAX(p.CreationDate)                                      AS LastPostDate
    FROM Users u
    LEFT JOIN Posts      p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges    b ON b.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id)                                 AS TaggedQuestionCount,
        AVG(p.Score)                                         AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') 
            FILTER (WHERE u.Id IS NOT NULL)                  AS TopContributors
    FROM Tags t
    LEFT JOIN Posts p
        ON p.PostTypeId = 1
        AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
),
RecentClosed AS (
    SELECT
        ph.PostId,
        ph.CreationDate                                   AS CloseDate,
        CAST(ph.Comment AS INT)                           AS CloseReasonId,
        COALESCE(cr.Name, 'Unknown')                      AS CloseReasonName
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr
        ON CAST(ph.Comment AS INT) = cr.Id
    WHERE ph.PostHistoryTypeId = 10
),
PostVotes AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        MAX(v.CreationDate)                      AS LastVoteDate
    FROM Votes v
    GROUP BY v.PostId
)

SELECT
    us.Id                                            AS UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.QuestionScoreSum,
    us.AnswerScoreSum,
    us.BadgeCount,
    us.LastPostDate,
    COALESCE(pv.UpVotes, 0)                          AS TotalUpVotes,
    COALESCE(pv.DownVotes, 0)                        AS TotalDownVotes,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC,
                                 us.BadgeCount DESC) AS ReputationRank,
    CASE
        WHEN us.AnswerCount = 0 THEN NULL
        ELSE ROUND(us.AnswerScoreSum::numeric / us.AnswerCount, 2)
    END                                            AS AvgAnswerScore,
    rc.CloseReasonName,
    rc.CloseDate
FROM UserStats us
LEFT JOIN LATERAL (
        SELECT pv.UpVotes, pv.DownVotes
        FROM PostVotes pv
        WHERE pv.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = us.Id
            ORDER BY p.CreationDate DESC
            LIMIT 1
        )
    ) pv ON TRUE
LEFT JOIN LATERAL (
        SELECT rc.CloseReasonName, rc.CloseDate
        FROM RecentClosed rc
        WHERE rc.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = us.Id
            ORDER BY p.CreationDate DESC
            LIMIT 1
        )
        ORDER BY rc.CloseDate DESC
        LIMIT 1
    ) rc ON TRUE
WHERE us.Reputation > 1000
ORDER BY ReputationRank
LIMIT 100

UNION ALL

SELECT
    NULL                                    AS UserId,
    ts.TagName                              AS DisplayName,
    NULL                                    AS Reputation,
    NULL                                    AS QuestionCount,
    NULL                                    AS AnswerCount,
    NULL                                    AS QuestionScoreSum,
    NULL                                    AS AnswerScoreSum,
    NULL                                    AS BadgeCount,
    NULL                                    AS LastPostDate,
    NULL                                    AS TotalUpVotes,
    NULL                                    AS TotalDownVotes,
    ROW_NUMBER() OVER (ORDER BY ts.TaggedQuestionCount DESC) AS ReputationRank,
    NULL                                    AS AvgAnswerScore,
    NULL                                    AS CloseReasonName,
    NULL                                    AS CloseDate
FROM TagStats ts
ORDER BY ReputationRank
LIMIT 50;
