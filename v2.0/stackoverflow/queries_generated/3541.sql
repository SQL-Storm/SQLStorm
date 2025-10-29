-- {"query": "3541.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2415} 

/*  Elaborate benchmark query for the StackOverflow schema  */
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)                         AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                                 AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                                 AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                                 AS BronzeBadges,
        MAX(p.CreationDate) FILTER (WHERE p.PostTypeId = 1)                    AS LastQuestionDate,
        MAX(p.CreationDate) FILTER (WHERE p.PostTypeId = 2)                    AS LastAnswerDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                            AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                            AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)                     AS UpVoteGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)                     AS DownVoteGiven
    FROM Users u
    LEFT JOIN Badges       b ON b.UserId = u.Id
    LEFT JOIN Posts        p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes        v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TopUsers AS (
    SELECT
        *,
        RANK()    OVER (ORDER BY Reputation DESC, NetVotes DESC)           AS RepRank,
        ROW_NUMBER() OVER (ORDER BY (GoldBadges*100 + SilverBadges*10 + BronzeBadges) DESC) AS BadgeScoreRank
    FROM UserStats
    WHERE Reputation IS NOT NULL
),

TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                         AS QuestionsWithTag,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                         AS AnswersWithTag,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                        AS AvgQuestionScore,
        MAX(p.CreationDate)                                                AS LatestActivity
    FROM Tags t
    LEFT JOIN Posts p
           ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 0
),

RecentCloseReasons AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        CAST(ph.Comment AS int)                                            AS CloseReasonId,
        COALESCE(crt.Name, 'Unknown')                                      AS CloseReasonName
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
    WHERE ph.PostHistoryTypeId = 10
      AND ph.Comment ~ '^\d+$'
),

UserCloseStats AS (
    SELECT
        u.Id,
        COUNT(*)                                                          AS ClosedPosts,
        COUNT(DISTINCT rc.CloseReasonId)                                 AS DistinctCloseReasons,
        STRING_AGG(DISTINCT rc.CloseReasonName, '; ')                    AS ReasonList
    FROM Users u
    JOIN Posts p           ON p.OwnerUserId = u.Id
    JOIN RecentCloseReasons rc ON rc.PostId = p.Id
    GROUP BY u.Id
)

SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.NetVotes,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.UpVoteGiven,
    tu.DownVoteGiven,
    tu.RepRank,
    tu.BadgeScoreRank,
    COALESCE(ucs.ClosedPosts,0)                                           AS ClosedPosts,
    COALESCE(ucs.DistinctCloseReasons,0)                                 AS DistinctCloseReasons,
    COALESCE(ucs.ReasonList,'')                                          AS CloseReasonList,
    CASE
        WHEN tu.QuestionCount = 0 THEN NULL
        ELSE ROUND(tu.AnswerCount::numeric / tu.QuestionCount, 2)
    END                                                                 AS AnswerToQuestionRatio,
    CASE
        WHEN tu.LastQuestionDate IS NULL THEN NULL
        ELSE DATE_PART('day', NOW() - tu.LastQuestionDate)
    END                                                                 AS DaysSinceLastQuestion,
    CASE
        WHEN tu.LastAnswerDate IS NULL THEN NULL
        ELSE DATE_PART('day', NOW() - tu.LastAnswerDate)
    END                                                                 AS DaysSinceLastAnswer
FROM TopUsers tu
LEFT JOIN UserCloseStats ucs ON ucs.Id = tu.Id
WHERE tu.RepRank <= 100
ORDER BY tu.RepRank

UNION ALL

SELECT
    NULL,
    '--- Tag Summary ---',
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
UNION ALL

SELECT
    NULL,
    t.TagName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    t.QuestionsWithTag,
    t.AnswersWithTag,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    ROUND(t.AvgQuestionScore::numeric,2),
    DATE_PART('day', NOW() - t.LatestActivity),
    NULL
FROM TagStats t
ORDER BY QuestionsWithTag DESC
LIMIT 150;
