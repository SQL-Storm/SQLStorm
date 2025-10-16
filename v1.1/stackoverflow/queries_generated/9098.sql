-- {"query": "9098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3076} 

WITH
-- aggregate per‐user posting & vote stats, plus a correlated subquery for avg answer score
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)                                 AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)                                 AS AnswersPosted,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN  1
                          WHEN v.VoteTypeId = 3 THEN -1
                          ELSE 0 END), 0)                                                      AS NetPostVotes,
        MAX(p.CreationDate)                                                                     AS LastPostDate,
        (SELECT AVG(a.Score)
           FROM Posts a
          WHERE a.OwnerUserId = u.Id
            AND a.PostTypeId   = 2
        )                                                                                       AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p  ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v  ON v.PostId       = p.Id
    GROUP BY
        u.Id,
        u.DisplayName
),
-- rank tags by their usage
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        DENSE_RANK() OVER (ORDER BY t.Count DESC)                                              AS TagRank
    FROM Tags t
),
-- gather recent comments per post as a concatenated string
LastComments AS (
    SELECT
        c.PostId,
        STRING_AGG(c.Text, ' ||| ' ORDER BY c.CreationDate DESC)                                AS RecentComments
    FROM Comments c
    GROUP BY c.PostId
),
-- a UNION ALL between high‐posting users and top tags as an example of a set operator
MetricUnion AS (
    SELECT
        Id         AS EntityId,
        DisplayName AS EntityName,
        QuestionsPosted        AS Metric
    FROM UserActivity
    WHERE QuestionsPosted > 100

    UNION ALL

    SELECT
        TagRank    AS EntityId,
        TagName    AS EntityName,
        Count      AS Metric
    FROM TopTags
    WHERE TagRank <= 10
)
SELECT
    ua.DisplayName,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.NetPostVotes,
    ua.AvgAnswerScore,
    COALESCE(ua.LastPostDate, NOW())                                                         AS LastSeen,
    tt.TagName,
    tt.Count                                                                               AS TagCount,
    lc.RecentComments,
    mu.Metric                                                                              AS TopMetric,
    CASE
      WHEN ua.LastPostDate < NOW() - INTERVAL '1 year' THEN 'Stale'
      WHEN ua.LastPostDate IS NULL             THEN 'Unknown'
      ELSE 'Active'
    END                                                                                     AS ActivityStatus,
    GREATEST(LENGTH(ua.DisplayName),
             COALESCE(ua.QuestionsPosted,0))                                                AS ComplexityScore
FROM UserActivity ua
FULL OUTER JOIN TopTags tt
    ON tt.TagRank = (ua.Id % 10) + 1
LEFT JOIN LastComments lc
    ON lc.PostId = (
        SELECT p2.Id
          FROM Posts p2
         WHERE p2.OwnerUserId = ua.Id
         ORDER BY p2.CreationDate DESC
         LIMIT 1
    )
LEFT JOIN MetricUnion mu
    ON mu.EntityId = COALESCE(ua.Id, tt.TagRank)
WHERE (ua.QuestionsPosted > 0 OR tt.TagRank <= 5)
ORDER BY ua.NetPostVotes DESC NULLS LAST,
         tt.Count        DESC NULLS LAST
LIMIT 100 OFFSET 0;
