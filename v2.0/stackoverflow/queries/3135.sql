-- {"query": "3135.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2456}
WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate    AS UserCreated,
        COALESCE(b.GoldBadges,   0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(v.UpVotes,   0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        (SELECT MAX(p.CreationDate)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY UserId
    ) v ON v.UserId = u.Id
),
TagStats AS (
    SELECT
        t.Id          AS TagId,
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score)                               AS AvgScore,
        MAX(p.CreationDate)                        AS LatestQuestionDate
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags IS NOT NULL
       AND POSITION(('<' || t.TagName || '>') IN p.Tags) > 0
    GROUP BY t.Id, t.TagName
),
RecentClosedQuestions AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate)                                           AS ClosedDate,
        MIN(ph.Comment) FILTER (WHERE ph.PostHistoryTypeId = 10)       AS CloseReason
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
TopActiveUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.Id) AS Rank
    FROM UserStats us
    WHERE us.Reputation > 10000
),
UserDetail AS (
    SELECT
        tu.Rank,
        tu.DisplayName,
        tu.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.UpVotes,
        us.DownVotes,
        COALESCE(us.LastPostDate, TIMESTAMP '1970-01-01')          AS LastPostDate,
        rcq.ClosedDate,
        rcq.CloseReason,
        STRING_AGG(DISTINCT ts.TagName, ', ') FILTER (WHERE ts.AvgScore > 0) AS RelevantTags
    FROM TopActiveUsers tu
    LEFT JOIN UserStats us ON us.Id = tu.Id
    LEFT JOIN Posts p
        ON p.OwnerUserId = tu.Id
       AND p.PostTypeId = 1
    LEFT JOIN RecentClosedQuestions rcq ON rcq.PostId = p.Id
    LEFT JOIN LATERAL (
        SELECT ts.TagName, ts.AvgScore
        FROM TagStats ts
        WHERE p.Tags IS NOT NULL
          AND POSITION(('<' || ts.TagName || '>') IN p.Tags) > 0
    ) ts ON TRUE
    GROUP BY
        tu.Rank, tu.DisplayName, tu.Reputation,
        us.GoldBadges, us.SilverBadges, us.BronzeBadges,
        us.UpVotes, us.DownVotes, us.LastPostDate,
        rcq.ClosedDate, rcq.CloseReason
),
TagLeaderboard AS (
    SELECT
        CAST(NULL AS INTEGER) AS Rank,
        CAST(NULL AS VARCHAR)    AS DisplayName,
        CAST(NULL AS BIGINT)  AS Reputation,
        CAST(NULL AS INTEGER) AS GoldBadges,
        CAST(NULL AS INTEGER) AS SilverBadges,
        CAST(NULL AS INTEGER) AS BronzeBadges,
        CAST(NULL AS INTEGER) AS UpVotes,
        CAST(NULL AS INTEGER) AS DownVotes,
        CAST(NULL AS TIMESTAMP) AS LastPostDate,
        CAST(NULL AS TIMESTAMP) AS ClosedDate,
        CAST(NULL AS VARCHAR)      AS CloseReason,
        STRING_AGG(ts.TagName, ', ') AS RelevantTags,
        ts.QuestionCount,
        ts.AnswerCount,
        ts.AvgScore,
        ts.LatestQuestionDate
    FROM TagStats ts
    WHERE ts.QuestionCount > 5000
    GROUP BY
        ts.QuestionCount, ts.AnswerCount,
        ts.AvgScore, ts.LatestQuestionDate
    ORDER BY ts.QuestionCount DESC
    LIMIT 20
)
SELECT
    Rank,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UpVotes,
    DownVotes,
    LastPostDate,
    ClosedDate,
    CloseReason,
    RelevantTags
FROM UserDetail
WHERE Rank <= 50

UNION ALL

SELECT
    Rank,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UpVotes,
    DownVotes,
    LastPostDate,
    ClosedDate,
    CloseReason,
    RelevantTags
FROM TagLeaderboard

ORDER BY
    Rank NULLS LAST,
    Reputation DESC NULLS LAST;