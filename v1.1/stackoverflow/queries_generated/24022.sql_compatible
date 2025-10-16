WITH question_metrics AS (
    SELECT
        p.Id                                               AS QuestionId,
        p.Title,
        p.Tags,
        u.DisplayName,
        u.Reputation,
        p.AnswerCount,
        p.ViewCount,
        p.Score                                            AS QuestionScore,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END)        AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END)        AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END)                                AS NetVotes,
        COALESCE(a.AvgScore, 0)                             AS AvgAnswerScore,
        COALESCE(a.MaxScore, 0)                             AS MaxAnswerScore,
        COALESCE(a.MaxScoreAnswerId, -1)                    AS MaxScoreAnswerId
    FROM
        Posts p
        JOIN Users u
            ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v
            ON v.PostId = p.Id
        LEFT JOIN LATERAL (
            SELECT
                AVG(a.Score)                               AS AvgScore,
                MAX(a.Score)                               AS MaxScore,
                -- compute id of one answer having the max score deterministically
                MAX(CASE WHEN a.Score = MAX_SCORE_PER_PARENT.max_score THEN a.Id END) AS MaxScoreAnswerId
            FROM
                Posts a
                CROSS JOIN (
                    SELECT MAX(a2.Score) AS max_score
                    FROM Posts a2
                    WHERE a2.ParentId = p.Id
                      AND a2.PostTypeId = 2
                ) AS MAX_SCORE_PER_PARENT
            WHERE
                a.ParentId = p.Id
                AND a.PostTypeId = 2
        ) a ON TRUE
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
    GROUP BY
        p.Id,
        p.Title,
        p.Tags,
        u.DisplayName,
        u.Reputation,
        p.AnswerCount,
        p.ViewCount,
        p.Score,
        a.AvgScore,
        a.MaxScore,
        a.MaxScoreAnswerId
),
tag_stats AS (
    SELECT
        qm.QuestionId,
        t.TagName,
        COUNT(*)                          OVER (PARTITION BY t.TagName)    AS TotalQuestionsForTag,
        SUM(qm.ViewCount)                 OVER (PARTITION BY t.TagName)    AS TotalViewsForTag,
        SUM(qm.AnswerCount)               OVER (PARTITION BY t.TagName)    AS TotalAnswersForTag
    FROM
        question_metrics qm
        JOIN LATERAL (
            SELECT
                regexp_split_to_array(
                    regexp_replace(qm.Tags, '(^<)|(>$)', '', 'g'),
                    '><'
                )                                 AS tags_arr
        ) AS tag_arr ON TRUE
        JOIN LATERAL UNNEST(tag_arr.tags_arr) AS taglist(tagname) ON TRUE
        JOIN Tags t
            ON t.TagName = taglist.tagname
)
SELECT
    qm.*,
    ts.TotalQuestionsForTag,
    ts.TotalViewsForTag,
    ts.TotalAnswersForTag,
    COALESCE(qm.NetVotes, 0)                                         AS NetVotesFixed,
    CASE
        WHEN ts.TotalAnswersForTag > 20 THEN 'High'
        WHEN ts.TotalAnswersForTag BETWEEN 5 AND 20 THEN 'Medium'
        ELSE 'Low'
    END                                                             AS EngagementLevel
FROM
    question_metrics qm
    JOIN tag_stats ts
        ON ts.QuestionId = qm.QuestionId
WHERE
    ts.TotalAnswersForTag > 0
UNION ALL
SELECT
    qm.*,
    ts.TotalQuestionsForTag,
    ts.TotalViewsForTag,
    ts.TotalAnswersForTag,
    COALESCE(qm.NetVotes, 0)                                         AS NetVotesFixed,
    CASE
        WHEN ts.TotalAnswersForTag > 20 THEN 'High'
        WHEN ts.TotalAnswersForTag BETWEEN 5 AND 20 THEN 'Medium'
        ELSE 'Low'
    END                                                             AS EngagementLevel
FROM
    question_metrics qm
    JOIN tag_stats ts
        ON ts.QuestionId = qm.QuestionId
WHERE
    ts.TotalAnswersForTag = 0
ORDER BY
    NetVotesFixed DESC,
    TotalQuestionsForTag DESC
LIMIT 100;