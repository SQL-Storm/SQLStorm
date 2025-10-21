-- {"query": "39008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3456} 

WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId AS UserId,
        u.Reputation
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
QuestionTag AS (
    SELECT
        rq.Id    AS PostId,
        unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS Tag
    FROM RecentQuestions rq
),
TagStats AS (
    SELECT
        qt.Tag,
        COUNT(*)             AS QuestionCount,
        AVG(rq.Score)        AS AvgScore,
        AVG(rq.ViewCount)    AS AvgViewCount,
        MAX(rq.Score)        AS MaxScore
    FROM QuestionTag qt
    JOIN RecentQuestions rq
      ON rq.Id = qt.PostId
    GROUP BY qt.Tag
),
TopTagUsers AS (
    SELECT
        qt.Tag,
        rq.UserId,
        COUNT(*)             AS QCount,
        ROW_NUMBER() OVER (
          PARTITION BY qt.Tag
          ORDER BY COUNT(*) DESC
        )                     AS rn
    FROM QuestionTag qt
    JOIN RecentQuestions rq
      ON rq.Id = qt.PostId
    GROUP BY qt.Tag, rq.UserId
),
TopUsers AS (
    SELECT
        Tag,
        UserId,
        QCount
    FROM TopTagUsers
    WHERE rn = 1
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '1 year'
    GROUP BY b.UserId
),
VoteSummary AS (
    SELECT
        qt.Tag,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)   AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM QuestionTag qt
    JOIN Votes v
      ON v.PostId = qt.PostId
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    GROUP BY qt.Tag
)
SELECT
    ts.Tag,
    ts.QuestionCount,
    ts.AvgScore,
    ts.AvgViewCount,
    ts.MaxScore,
    tu.UserId      AS TopUserId,
    u.DisplayName  AS TopUser,
    COALESCE(bs.GoldBadges,   0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(vs.UpVotes,      0) AS UpVotes,
    COALESCE(vs.DownVotes,    0) AS DownVotes
FROM TagStats ts
LEFT JOIN TopUsers tu
  ON ts.Tag = tu.Tag
LEFT JOIN Users u
  ON tu.UserId = u.Id
LEFT JOIN BadgeSummary bs
  ON tu.UserId = bs.UserId
LEFT JOIN VoteSummary vs
  ON ts.Tag = vs.Tag
ORDER BY
    ts.QuestionCount DESC,
    ts.AvgScore     DESC
LIMIT 20;
