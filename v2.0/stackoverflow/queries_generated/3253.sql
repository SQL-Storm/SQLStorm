-- {"query": "3253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2089} 

/*  Complex performance‑benchmark query using CTEs, window functions, outer joins,
    correlated subqueries, set operators, string handling and NULL logic          */
WITH
    /* Basic per‑user aggregates */
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.Location, '[unknown]')                     AS Location,
            /* last activity of the user (any post) */
            (SELECT MAX(p.CreationDate)
             FROM Posts p
             WHERE p.OwnerUserId = u.Id)                        AS LastPostDate,
            /* total badges earned */
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
            /* count of questions and answers */
            (SELECT COUNT(*) FROM Posts q WHERE q.OwnerUserId = u.Id AND q.PostTypeId = 1) AS QuestionCount,
            (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS AnswerCount,
            /* average up‑vote score on all user's posts */
            (SELECT AVG(v.Score)
             FROM Votes v
             JOIN Posts p ON v.PostId = p.Id
             WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2)   AS AvgUpVotes
        FROM Users u
    ),

    /* Tag usage statistics (only for tags appearing in question bodies) */
    TagUsage AS (
        SELECT
            t.TagName,
            COUNT(p.Id)                                          AS QuestionWithTag,
            SUM(p.Score)                                         AS TotalScore,
            ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC)       AS TagRank
        FROM Tags t
        JOIN Posts p
          ON p.PostTypeId = 1
         AND p.Tags LIKE CONCAT('%', t.TagName, '%')
        GROUP BY t.TagName
    ),

    /* Most recent closed‑question history entry per post */
    RecentClosed AS (
        SELECT
            ph.PostId,
            ph.CreationDate                                      AS ClosedDate,
            ph.Comment                                           AS CloseReasonId,
            ROW_NUMBER() OVER (PARTITION BY ph.PostId
                               ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10               -- Post Closed
    ),

    /* Rank users by reputation (ties broken by badge count) */
    TopUsers AS (
        SELECT
            us.*,
            RANK() OVER (ORDER BY us.Reputation DESC, us.BadgeCount DESC) AS RepRank,
            CASE WHEN us.LastPostDate IS NULL THEN 1 ELSE 0 END            AS IsInactive
        FROM UserStats us
    )

/* -------------------------------------------------------------------------- */
/* Main result set – top 100 users with rich derived columns                */
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.RepRank,
    tu.BadgeCount,
    tu.QuestionCount,
    tu.AnswerCount,
    COALESCE(tu.AvgUpVotes, 0)                                AS AvgUpVotes,
    tu.IsInactive,
    COALESCE(rc.ClosedDate, TIMESTAMP '1900-01-01 00:00:00')  AS LastClosedDate,
    COALESCE(rc.CloseReasonId, '0')                          AS LastCloseReasonId,
    COALESCE(tu.LastPostDate, TIMESTAMP '1900-01-01 00:00:00') AS LastPostDate,
    tu.Location,
    /* custom activity score */
    (COALESCE(tu.QuestionCount,0) * 0.1 +
     COALESCE(tu.AnswerCount,0)   * 0.2)                     AS ActivityScore,
    CASE
        WHEN tu.Reputation > 20000 THEN 'Legend'
        WHEN tu.Reputation > 10000 THEN 'Expert'
        WHEN tu.Reputation > 5000  THEN 'Contributor'
        ELSE 'Newbie'
    END                                                       AS ReputationTier
FROM TopUsers tu
LEFT JOIN RecentClosed rc
       ON rc.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = tu.Id
              AND p.PostTypeId = 1               -- only questions
            ORDER BY p.CreationDate DESC
            LIMIT 1
          )
      AND rc.rn = 1
WHERE tu.RepRank <= 100

/* -------------------------------------------------------------------------- */
/* Append an aggregated summary row (set operator)                           */
UNION ALL
SELECT
    NULL                                                     AS Id,
    'Aggregate Summary'                                      AS DisplayName,
    NULL                                                     AS Reputation,
    NULL                                                     AS RepRank,
    SUM(BadgeCount)                                          AS BadgeCount,
    SUM(QuestionCount)                                       AS QuestionCount,
    SUM(AnswerCount)                                         AS AnswerCount,
    AVG(AvgUpVotes)                                          AS AvgUpVotes,
    NULL                                                     AS IsInactive,
    NULL                                                     AS LastClosedDate,
    NULL                                                     AS LastCloseReasonId,
    NULL                                                     AS LastPostDate,
    NULL                                                     AS Location,
    NULL                                                     AS ActivityScore,
    NULL                                                     AS ReputationTier
FROM TopUsers
ORDER BY
    ReputationTier DESC NULLS LAST,
    RepRank;
