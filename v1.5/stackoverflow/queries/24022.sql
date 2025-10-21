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
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)         AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)         AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                  WHEN v.VoteTypeId = 3 THEN -1
                  ELSE 0 END)                            AS NetVotes,
        COALESCE(a.AvgScore, 0)                            AS AvgAnswerScore,
        COALESCE(a.MaxScore, 0)                            AS MaxAnswerScore,
        COALESCE(a.MaxScoreAnswerId, -1)                   AS MaxScoreAnswerId
    FROM
        Posts p
        JOIN Users u
            ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v
            ON v.PostId = p.Id
        LEFT JOIN LATERAL (
            SELECT
                AVG(a.Score)                            AS AvgScore,
                MAX(a.Score)                            AS MaxScore,
                MAX(a.Id) FILTER (WHERE a.Score = (SELECT MAX(b.Score) FROM Posts b WHERE b.ParentId = p.Id AND b.PostTypeId = 2)) AS MaxScoreAnswerId
            FROM
                Posts a
            WHERE
                a.ParentId = p.Id
                AND a.PostTypeId = 2
        ) a ON TRUE
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30 days'
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
        CROSS JOIN LATERAL (
            SELECT
                REGEXP_SPLIT_TO_TABLE(REGEXP_REPLACE(qm.Tags, '(^<)|(>$)', '', 'g'), '><') AS tagname
        ) AS taglist
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