-- {"query": "3294.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2663} 

-- Complex benchmark query using the StackOverflow schema
WITH
    -- Basic user aggregates
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)          AS NetVotes,
            (
                SELECT COUNT(*) FROM Badges b
                WHERE b.UserId = u.Id AND b.Class = 1
            )                                                          AS GoldBadges,
            (
                SELECT COUNT(*) FROM Badges b
                WHERE b.UserId = u.Id AND b.Class = 2
            )                                                          AS SilverBadges,
            (
                SELECT COUNT(*) FROM Badges b
                WHERE b.UserId = u.Id AND b.Class = 3
            )                                                          AS BronzeBadges
        FROM Users u
        WHERE u.Reputation IS NOT NULL
    ),

    -- Tag‑level statistics for questions
    TagStats AS (
        SELECT
            t.TagName,
            COUNT(p.Id)                                            AS QuestionCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)       AS AvgScore,
            STRING_AGG(DISTINCT LEFT(p.Title, 60), '; ')           AS SampleTitles
        FROM Tags t
        JOIN Posts p
          ON p.Tags LIKE CONCAT('%', t.TagName, '%')
        WHERE p.PostTypeId = 1          -- only questions
        GROUP BY t.TagName
    ),

    -- Most recent activity per user
    RecentActivity AS (
        SELECT
            p.OwnerUserId,
            MAX(p.LastActivityDate)                               AS LastActivity
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- Close‑reason extraction (correlated subquery via CTE)
    ClosedReasons AS (
        SELECT
            ph.PostId,
            MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)   AS CloseReasonId,
            MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedOn
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ),

    -- Per‑user question/answer metrics
    UserQuestionStats AS (
        SELECT
            p.OwnerUserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)                AS QCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)                AS ACount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)           AS AvgQuestionScore,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)           AS AvgAnswerScore,
            SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAccepted,
            SUM(COALESCE(p.FavoriteCount,0))                       AS TotalFavorites
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- Rank users by reputation + net votes
    RankedUsers AS (
        SELECT
            us.Id,
            us.DisplayName,
            us.Reputation,
            us.NetVotes,
            us.GoldBadges,
            us.SilverBadges,
            us.BronzeBadges,
            uq.QCount,
            uq.ACount,
            uq.AvgQuestionScore,
            uq.AvgAnswerScore,
            uq.QuestionsWithAccepted,
            uq.TotalFavorites,
            ra.LastActivity,
            ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC) AS RepRank
        FROM UserStats us
        LEFT JOIN UserQuestionStats uq ON uq.OwnerUserId = us.Id
        LEFT JOIN RecentActivity ra   ON ra.OwnerUserId = us.Id
    )

-- Final result set: top 100 users with their best tag and a summary row
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.NetVotes,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QCount,
    ru.ACount,
    ROUND(ru.AvgQuestionScore::numeric, 2) AS AvgQuestionScore,
    ROUND(ru.AvgAnswerScore::numeric, 2)   AS AvgAnswerScore,
    ru.QuestionsWithAccepted,
    ru.TotalFavorites,
    ru.LastActivity,
    ru.RepRank,
    COALESCE(ts.TagName, 'NoTag')           AS TopTag,
    ts.QuestionCount                        AS TagQuestionCount,
    ROUND(ts.AvgScore::numeric, 2)          AS TagAvgScore,
    ts.SampleTitles                         AS TagSampleTitles
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT
        t.TagName,
        t.QuestionCount,
        t.AvgScore,
        t.SampleTitles
    FROM TagStats t
    ORDER BY t.QuestionCount DESC
    LIMIT 1
) ts ON TRUE
WHERE ru.RepRank <= 100
  AND (ru.LastActivity IS NULL OR ru.LastActivity > CURRENT_DATE - INTERVAL '1 year')

UNION ALL

-- Summary row (set operator usage)
SELECT
    NULL                                 AS Id,
    '--- Summary ---'                    AS DisplayName,
    NULL                                 AS Reputation,
    NULL                                 AS NetVotes,
    NULL                                 AS GoldBadges,
    NULL                                 AS SilverBadges,
    NULL                                 AS BronzeBadges,
    (SELECT COUNT(*) FROM Users)         AS QCount,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) AS ACount,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AvgQuestionScore,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) AS AvgAnswerScore,
    (SELECT COUNT(DISTINCT OwnerUserId) FROM Posts WHERE AcceptedAnswerId IS NOT NULL) AS QuestionsWithAccepted,
    (SELECT SUM(COALESCE(FavoriteCount,0)) FROM Posts) AS TotalFavorites,
    NULL                                 AS LastActivity,
    NULL                                 AS RepRank,
    NULL                                 AS TopTag,
    NULL                                 AS TagQuestionCount,
    NULL                                 AS TagAvgScore,
    NULL                                 AS TagSampleTitles
ORDER BY RepRank NULLS LAST, Id;
