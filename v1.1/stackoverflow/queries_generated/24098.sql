-- {"query": "24098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4221} 

WITH
    question_posts AS (
        SELECT
            p.Id AS QuestionId,
            p.Title,
            p.Tags,
            p.CreationDate,
            p.ViewCount,
            p.Score,
            p.OwnerUserId,
            COUNT(DISTINCT c.Id)                                        AS CommentCount,
            COUNT(DISTINCT a.Id)                                        AS AnswerCount
        FROM Posts p
        LEFT JOIN Comments c  ON c.PostId     = p.Id
        LEFT JOIN Posts a     ON a.ParentId   = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY
            p.Id, p.Title, p.Tags, p.CreationDate,
            p.ViewCount, p.Score, p.OwnerUserId
    ),

    tag_explode AS (
        SELECT
            qp.QuestionId,
            TAGNAME
        FROM question_posts qp
        CROSS APPLY STRING_SPLIT(qp.Tags, '><') AS s
        OUTER APPLY (
            SELECT NULLIF(s.value, '') AS TAGNAME
        ) t
        WHERE t.TAGNAME IS NOT NULL
    ),

    tag_stats AS (
        SELECT
            TAGNAME              AS TagName,
            SUM(AnswerCount)     AS TotalAnswers,
            SUM(CommentCount)    AS TotalComments,
            SUM(ViewCount)       AS TotalViews,
            COUNT(DISTINCT QuestionId) AS QuestionCount
        FROM (
            SELECT
                qp.QuestionId,
                qp.Tags,
                qp.AnswerCount,
                qp.CommentCount,
                qp.ViewCount
            FROM question_posts qp
        ) qp
        INNER JOIN tag_explode te ON CHARINDEX('<' + te.TAGNAME + '>', qp.Tags) > 0
        GROUP BY TAGNAME
    ),

    user_badges AS (
        SELECT
            u.Id                                     AS UserId,
            u.DisplayName,
            COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 END),0) AS GoldBadges,
            COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 END),0) AS SilverBadges,
            COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 END),0) AS BronzeBadges,
            COALESCE(COUNT(b.Id),0)                AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName
    ),

    vote_stats AS (
        SELECT
            p.Id                                           AS PostId,
            COUNT(v.Id)                                    AS VoteCount,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.Id
    ),

    last_edits AS (
        SELECT
            ph.PostId,
            MAX(ph.CreationDate)                          AS LastEdit
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4,5,6)
        GROUP BY ph.PostId
    )

SELECT
    qp.QuestionId,
    qp.Title,
    qp.Tags,
    qp.Score,
    qp.ViewCount,
    qp.AnswerCount,
    qp.CommentCount,
    ts.TagName,
    ts.TotalAnswers,
    ts.TotalComments,
    ts.TotalViews,
    ub.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    vs.VoteCount,
    vs.UpVotes,
    vs.DownVotes,
    le.LastEdit,
    CASE
        WHEN qp.ViewCount > 1000 AND qp.Score > 5 THEN 'High Impact'
        WHEN qp.Score = 0 AND qp.AnswerCount = 0 THEN 'Unanswered'
        ELSE 'Regular'
    END                                                        AS PostCategory
FROM question_posts qp
LEFT JOIN tag_stats ts
       ON CHARINDEX('<' + ts.TagName + '>', qp.Tags) > 0
LEFT JOIN user_badges ub
       ON ub.UserId = qp.OwnerUserId
LEFT JOIN vote_stats vs
       ON vs.PostId = qp.QuestionId
LEFT JOIN last_edits le
       ON le.PostId = qp.QuestionId
WHERE qp.CreationDate >= DATEADD(year, -1, GETDATE())
  AND qp.ViewCount > ISNULL(vs.VoteCount, 0) * 10
UNION ALL
SELECT
    p.Id                    AS QuestionId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    NULL                     AS TagName,
    NULL                     AS TotalAnswers,
    NULL                     AS TotalComments,
    NULL                     AS TotalViews,
    NULL                     AS DisplayName,
    0                        AS GoldBadges,
    0                        AS SilverBadges,
    0                        AS BronzeBadges,
    0                        AS TotalBadges,
    COALESCE(vs.VoteCount, 0) AS VoteCount,
    COALESCE(vs.UpVotes, 0)   AS UpVotes,
    COALESCE(vs.DownVotes, 0) AS DownVotes,
    NULL                     AS LastEdit,
    'Other'                  AS PostCategory
FROM Posts p
LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = p.Id
LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
LEFT JOIN vote_stats vs ON vs.PostId = p.Id
WHERE p.PostTypeId = 1
  AND p.ViewCount < 100;
