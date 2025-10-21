WITH top_tags AS (
    SELECT t.Id, t.TagName
    FROM Tags t
    WHERE t.Count > 1000
    ORDER BY t.Count DESC
    LIMIT 10
),
user_activity AS (
    SELECT
        u.Id                         AS UserId,
        u.DisplayName,
        COUNT(p.Id)                  AS QuestionCount,
        COALESCE(SUM(p.Score),0)     AS TotalScore,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)   AS UpVotesGiven,
        COUNT(vb.Id) FILTER (WHERE vb.VoteTypeId = 8) AS BountiesStarted
    FROM Users u
    LEFT JOIN Posts p  ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Votes v  ON v.UserId = u.Id
    LEFT JOIN Votes vb ON vb.UserId = u.Id AND vb.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName
),
tag_activity AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                                          AS QuestionCount,
        COALESCE(SUM(p.Score),0)                             AS TotalScore,
        AVG(p.AnswerCount)                                   AS AvgAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews,
        COUNT(DISTINCT ph.UserId)                            AS DistinctEditors
    FROM Tags t
    JOIN Posts p
        ON p.PostTypeId = 1
       AND p.Tags LIKE ('%<'||t.TagName||'>%')
    LEFT JOIN PostHistory ph
        ON ph.PostId = p.Id
       AND ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50
)
SELECT
    ta.TagName,
    ta.QuestionCount,
    ta.TotalScore,
    ta.AvgAnswers,
    ta.MedianViews,
    ta.DistinctEditors,
    ua.DisplayName,
    ua.QuestionCount  AS UserQuestions,
    ua.TotalScore     AS UserScore,
    ua.UpVotesGiven,
    ua.BountiesStarted,
    ROW_NUMBER() OVER (PARTITION BY ta.TagName ORDER BY ua.TotalScore DESC) AS UserRankInTag
FROM tag_activity ta
JOIN top_tags tt ON tt.TagName = ta.TagName
JOIN LATERAL (
    SELECT *
    FROM user_activity ua
    WHERE EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = ua.UserId
          AND p.PostTypeId = 1
          AND p.Tags LIKE ('%<'||ta.TagName||'>%')
    )
    ORDER BY ua.TotalScore DESC
    LIMIT 5
) ua ON TRUE
ORDER BY ta.TotalScore DESC, UserRankInTag;