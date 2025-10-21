-- {"query": "3039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 750} 
WITH PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
),
RecentPostTypes AS (
    SELECT DISTINCT
        pts.PostTypeId
    FROM
        PostStats pts
    WHERE
        pts.PostRank <= 5
),
ActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplay,
        p.Score,
        p.Tags,
        p.AnswerCount,
        p.CommentCount
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '30 days'
        AND p.Tags IS NOT NULL
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
    GROUP BY
        a.ParentId
),
QuestionDetails AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerDisplay,
        q.Score,
        q.Tags,
        q.AnswerCount,
        q.CommentCount,
        COALESCE(a.AnswerCount, 0) AS TotalAnswers,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore
    FROM
        ActiveQuestions q
    LEFT JOIN
        AnswerStats a ON q.QuestionId = a.QuestionId
),
RecentQuestions AS (
    SELECT
        *
    FROM
        QuestionDetails
    WHERE
        CreationDate >= NOW() - INTERVAL '30 days'
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerDisplay,
    rq.Score,
    string_agg(t.TagName, ', ' ORDER BY t.TagName) AS Tags,
    rq.AnswerCount,
    rq.CommentCount,
    rq.TotalAnswers,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    CASE WHEN rs.PostTypeId IS NULL THEN 'Other' ELSE 'Question/Answer' END AS TypeCategory
FROM
    RecentQuestions rq
LEFT JOIN
    Posts p ON rq.QuestionId = p.Id
LEFT JOIN
    unnest(string_to_array(rq.Tags, ',')) WITH ORDINALITY AS t(TagName, idx) ON TRUE
LEFT JOIN
    RecentPostTypes rs ON p.PostTypeId = rs.PostTypeId
WHERE
    (p.PostTypeId IN (1, 2))
GROUP BY
    rq.QuestionId, rq.Title, rq.CreationDate, rq.OwnerDisplay, rq.Score, rq.AnswerCount, rq.CommentCount, rq.TotalAnswers, rq.AvgAnswerScore, rq.MaxAnswerScore, rs.PostTypeId;