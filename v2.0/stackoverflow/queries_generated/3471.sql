-- {"query": "3471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2556} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END) AS NetVoteScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c       ON c.UserId = u.Id
    LEFT JOIN Badges b         ON b.UserId = u.Id
    LEFT JOIN Votes v          ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
TagUsage AS (
    SELECT
        u.Id                                   AS UserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*)                               AS TagPostCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
                 AND p.PostTypeId = 1
                 AND p.Tags IS NOT NULL
    GROUP BY u.Id, Tag
),
TopTags AS (
    SELECT
        UserId,
        STRING_AGG(Tag || ':' || TagPostCount, ', ' ORDER BY TagPostCount DESC) AS TopTags
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC) AS rn
        FROM TagUsage
    ) t
    WHERE rn <= 5
    GROUP BY UserId
),
RecentClosedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        ph.CreationDate               AS ClosedDate,
        COALESCE(NULLIF(ph.Comment, ''), 'NoReason') AS CloseReason,
        u.Id                          AS OwnerId,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    JOIN Users u        ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
UserCloseStats AS (
    SELECT
        OwnerId                     AS UserId,
        COUNT(*) FILTER (WHERE rn = 1) AS MostRecentClosedCount,
        MIN(ClosedDate)                 AS FirstClosedDate,
        MAX(ClosedDate)                 AS LastClosedDate
    FROM RecentClosedQuestions
    GROUP BY OwnerId
),
Combined AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.CommentCount,
        us.BadgeCount,
        us.NetVoteScore,
        us.AvgQuestionScore,
        us.AvgAnswerScore,
        COALESCE(tt.TopTags, '')                AS TopTags,
        COALESCE(ucs.MostRecentClosedCount,0)   AS RecentClosedCount,
        COALESCE(ucs.FirstClosedDate,
                 TIMESTAMP '1970-01-01')       AS FirstClosed,
        COALESCE(ucs.LastClosedDate,
                 TIMESTAMP '1970-01-01')       AS LastClosed,
        RANK() OVER (ORDER BY us.Reputation DESC) AS ReputationRank,
        CASE
            WHEN us.Reputation > 200000 THEN 'Legendary'
            WHEN us.Reputation > 100000 THEN 'Epic'
            WHEN us.Reputation > 50000  THEN 'Veteran'
            ELSE 'Member'
        END                                    AS ReputationTier
    FROM UserStats us
    LEFT JOIN TopTags tt   ON tt.UserId = us.Id
    LEFT JOIN UserCloseStats ucs ON ucs.UserId = us.Id
)
SELECT *
FROM Combined
WHERE ReputationRank <= 100
   OR (RecentClosedCount > 0 AND ReputationTier = 'Veteran')
ORDER BY ReputationRank
UNION ALL
SELECT
    NULL                              AS Id,
    'Summary'                         AS DisplayName,
    NULL                              AS Reputation,
    SUM(QuestionCount)                AS QuestionCount,
    SUM(AnswerCount)                  AS AnswerCount,
    SUM(CommentCount)                 AS CommentCount,
    SUM(BadgeCount)                   AS BadgeCount,
    SUM(NetVoteScore)                 AS NetVoteScore,
    AVG(AvgQuestionScore)             AS AvgQuestionScore,
    AVG(AvgAnswerScore)               AS AvgAnswerScore,
    NULL                              AS TopTags,
    SUM(RecentClosedCount)            AS RecentClosedCount,
    MIN(FirstClosed)                  AS FirstClosed,
    MAX(LastClosed)                   AS LastClosed,
    NULL                              AS ReputationRank,
    NULL                              AS ReputationTier
FROM Combined
WHERE ReputationRank <= 100
   OR (RecentClosedCount > 0 AND ReputationTier = 'Veteran')
ORDER BY ReputationRank NULLS LAST;
