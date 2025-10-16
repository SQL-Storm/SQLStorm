WITH
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS NetPostVotes,
        MAX(p.CreationDate) AS LastPostDate,
        (SELECT AVG(a.Score)
           FROM Posts a
          WHERE a.OwnerUserId = u.Id
            AND a.PostTypeId = 2
        ) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY
        u.Id,
        u.DisplayName
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
),
LastComments AS (
    SELECT
        c.PostId,
        STRING_AGG(c.Text, ' ||| ' ORDER BY c.CreationDate DESC) AS RecentComments
    FROM Comments c
    GROUP BY c.PostId
),
MetricUnion AS (
    SELECT
        Id AS EntityId,
        DisplayName AS EntityName,
        QuestionsPosted AS Metric
    FROM UserActivity
    WHERE QuestionsPosted > 100

    UNION ALL

    SELECT
        TagRank AS EntityId,
        TagName AS EntityName,
        Count AS Metric
    FROM TopTags
    WHERE TagRank <= 10
)
SELECT
    ua.DisplayName,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.NetPostVotes,
    ua.AvgAnswerScore,
    COALESCE(ua.LastPostDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) AS LastSeen,
    tt.TagName,
    tt.Count AS TagCount,
    lc.RecentComments,
    mu.Metric AS TopMetric,
    CASE
      WHEN ua.LastPostDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') THEN 'Stale'
      WHEN ua.LastPostDate IS NULL THEN 'Unknown'
      ELSE 'Active'
    END AS ActivityStatus,
    GREATEST(LENGTH(ua.DisplayName), COALESCE(ua.QuestionsPosted, 0)) AS ComplexityScore,
    ua.Id,
    tt.TagRank
FROM UserActivity ua
FULL OUTER JOIN TopTags tt
    ON tt.TagRank = ((ua.Id % 10) + 1)
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
WHERE (COALESCE(ua.QuestionsPosted, 0) > 0 OR tt.TagRank <= 5)
GROUP BY
    ua.DisplayName,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.NetPostVotes,
    ua.AvgAnswerScore,
    ua.LastPostDate,
    tt.TagName,
    tt.Count,
    lc.RecentComments,
    mu.Metric,
    ua.Id,
    tt.TagRank
ORDER BY ua.NetPostVotes DESC NULLS LAST,
         tt.Count DESC NULLS LAST
LIMIT 100 OFFSET 0;