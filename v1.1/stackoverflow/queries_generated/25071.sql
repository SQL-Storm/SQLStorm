-- {"query": "25071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2349} 

WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        COUNT(*) AS TotalVotesGiven
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
QuestionStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.Score >= 0) AS PositiveQuestionCount,
        COUNT(*) FILTER (WHERE p.Score < 0)  AS NegativeQuestionCount,
        AVG(p.ViewCount)::NUMERIC(10,2)      AS AvgViews,
        MAX(p.CreationDate)                 AS LastQuestionDate
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
AnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*)                               AS AnswerCount,
        SUM(CASE WHEN ph.Id IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        AVG(p.Score)::NUMERIC(10,2)            AS AvgScore,
        MAX(p.LastActivityDate)                AS LastActivity
    FROM Posts p
    LEFT JOIN PostHistory ph
        ON ph.PostId = p.Id
       AND ph.PostHistoryTypeId = 4   -- Edit Title (used as proxy for acceptance flag)
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
TagCooccurrence AS (
    SELECT
        t1.TagName AS TagA,
        t2.TagName AS TagB,
        COUNT(*)   AS CooccurCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
    ) AS pt1
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
    ) AS pt2
    JOIN Tags t1 ON t1.TagName = pt1.Tag
    JOIN Tags t2 ON t2.TagName = pt2.Tag
    WHERE pt1.Tag < pt2.Tag
    GROUP BY t1.TagName, t2.TagName
    HAVING COUNT(*) > 100
)
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.ReputationRank,
    COALESCE(ub.GoldCount, 0)       AS GoldBadges,
    COALESCE(ub.SilverCount, 0)     AS SilverBadges,
    COALESCE(ub.BronzeCount, 0)     AS BronzeBadges,
    COALESCE(ub.TagBadgeCount, 0)   AS TagBadges,
    COALESCE(uv.UpVotesGiven, 0)    AS UpVotesGiven,
    COALESCE(uv.DownVotesGiven, 0)  AS DownVotesGiven,
    COALESCE(qs.PositiveQuestionCount,0) -
    COALESCE(qs.NegativeQuestionCount,0) AS NetPositiveQuestions,
    COALESCE(qs.AvgViews,0)          AS AvgQuestionViews,
    COALESCE(as.AnswerCount,0)       AS TotalAnswers,
    COALESCE(as.AcceptedAnswerCount,0) AS AcceptedAnswers,
    COALESCE(as.AvgScore,0)          AS AvgAnswerScore,
    CASE
        WHEN COALESCE(as.AnswerCount,0) = 0 THEN NULL
        ELSE ROUND(100.0 * COALESCE(as.AcceptedAnswerCount,0) / as.AnswerCount, 2)
    END AS AcceptanceRatePct,
    (SELECT STRING_AGG(DISTINCT tc.TagB, ', ' ORDER BY tc.CooccurCount DESC)
     FROM TagCooccurrence tc
     WHERE tc.TagA = ANY (
         SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><'))
         FROM Posts p
         WHERE p.OwnerUserId = tu.Id
         LIMIT 1
     )
     LIMIT 5) AS TopCooccurringTags
FROM TopUsers tu
LEFT JOIN UserBadges  ub ON ub.UserId = tu.Id
LEFT JOIN UserVotes   uv ON uv.UserId = tu.Id
LEFT JOIN QuestionStats qs ON qs.UserId = tu.Id
LEFT JOIN AnswerStats   as ON as.UserId = tu.Id
WHERE tu.ReputationRank <= 1000
ORDER BY tu.ReputationRank;
