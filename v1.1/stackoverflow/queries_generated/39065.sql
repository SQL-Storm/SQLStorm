-- {"query": "39065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1584} 

WITH UserActivity AS (
    SELECT
        u.Id         AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)         AS AnswerCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)         AS QuestionCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)     AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC) AS UserRank
    FROM UserActivity ua
),
QuestionTags AS (
    SELECT
        p.Id         AS QuestionId,
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagExpertise AS (
    SELECT
        qt.UserId,
        qt.Tag,
        COUNT(*)        AS QuestionsWithTag,
        AVG(a.Score)    AS AvgAnswerScoreForTag
    FROM QuestionTags qt
    JOIN Posts a
      ON a.ParentId = qt.QuestionId
     AND a.PostTypeId = 2
    GROUP BY qt.UserId, qt.Tag
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
FinalReport AS (
    SELECT
        tu.UserRank,
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.AnswerCount,
        tu.QuestionCount,
        tu.AvgAnswerScore,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        te.Tag         AS TopTag,
        te.QuestionsWithTag,
        te.AvgAnswerScoreForTag
    FROM TopUsers tu
    LEFT JOIN BadgeSummary bs
      ON bs.UserId = tu.UserId
    LEFT JOIN LATERAL (
        SELECT te2.Tag,
               te2.QuestionsWithTag,
               te2.AvgAnswerScoreForTag
        FROM TagExpertise te2
        WHERE te2.UserId = tu.UserId
        ORDER BY te2.QuestionsWithTag DESC
        LIMIT 1
    ) te ON TRUE
    WHERE tu.UserRank <= 100
)
SELECT
    fr.*,
    DENSE_RANK() OVER (ORDER BY fr.AvgAnswerScore DESC) AS AnswerScoreRank
FROM FinalReport fr
ORDER BY fr.UserRank;
