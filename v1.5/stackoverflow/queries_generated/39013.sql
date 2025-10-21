-- {"query": "39013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2031} 

WITH
-- Break out question tags into one row per tag
ParsedTags AS (
    SELECT
        p.Id        AS QuestionId,
        unnest(
          string_to_array(
            substring(p.Tags, 2, length(p.Tags) - 2),
            '><'
          )
        )        AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),

-- Compute per‑question answer counts and average first‑answer latency
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*)                    AS AnswerCount,
        AVG(EXTRACT(
              EPOCH FROM (a.CreationDate - q.CreationDate)
            ))                       AS AvgResponseSeconds
    FROM Posts a
    JOIN Posts q
      ON q.Id = a.ParentId
     AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),

-- Count gold badges per user
GoldBadges AS (
    SELECT
        b.UserId,
        COUNT(*) AS GoldCount
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),

-- Summarize votes by user
UserScores AS (
    SELECT
        u.Id                     AS UserId,
        u.Reputation,
        COALESCE(g.GoldCount, 0) AS GoldBadges,
        COUNT(v.*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
    FROM Users u
    LEFT JOIN GoldBadges g ON g.UserId = u.Id
    LEFT JOIN Votes v      ON v.UserId = u.Id
    GROUP BY u.Id, u.Reputation, g.GoldCount
),

-- Count edits per post
EditsStats AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),

-- Aggregate per‑tag statistics
TagStats AS (
    SELECT
        pt.Tag,
        COUNT(DISTINCT pt.QuestionId)      AS QuestionCount,
        ROUND(AVG(as_.AnswerCount)::numeric, 2)     AS AvgAnswersPerQuestion,
        AVG(as_.AvgResponseSeconds)       AS AvgFirstAnswerSeconds,
        ROUND(AVG(COALESCE(es.EditCount, 0))::numeric, 2) AS AvgEditsPerQuestion
    FROM ParsedTags pt
    LEFT JOIN AnswerStats    as_ ON as_.QuestionId = pt.QuestionId
    LEFT JOIN EditsStats     es  ON es.PostId     = pt.QuestionId
    GROUP BY pt.Tag
)

SELECT
    ts.Tag,
    ts.QuestionCount,
    ts.AvgAnswersPerQuestion,
    to_char((ts.AvgFirstAnswerSeconds/3600)::interval, 'HH24:MI:SS') AS AvgTimeToFirstAnswer,
    ts.AvgEditsPerQuestion,
    topu.Reputation         AS TopUserReputation,
    topu.GoldBadges         AS TopUserGoldBadges,
    topq.Score              AS TopQuestionScore
FROM TagStats ts

-- For each tag, find the highest‑scoring question owner details
JOIN LATERAL (
    SELECT
        u2.Reputation,
        u2.GoldBadges,
        q2.Score
    FROM ParsedTags pt2
    JOIN Posts q2
      ON q2.Id = pt2.QuestionId
     AND q2.PostTypeId = 1
    JOIN UserScores u2
      ON u2.UserId = q2.OwnerUserId
    WHERE pt2.Tag = ts.Tag
    ORDER BY q2.Score DESC
    LIMIT 1
) AS topu ON true
ORDER BY ts.QuestionCount DESC
LIMIT 25;
