WITH
    question_posts AS (
        SELECT
            p.Id,
            p.Title,
            p.Tags,
            p.CreationDate,
            p.Score,
            u.Reputation AS OwnerRep,
            COALESCE(v.TotalVotes, 0) AS VoteCount,
            COALESCE(a.AnswerCount, 0) AS AnswerCount,
            ROW_NUMBER() OVER (PARTITION BY
                (
                    SELECT string_agg(tag, ',')
                    FROM unnest(string_to_array(p.Tags, '><')) AS tag(tag)
                )
                ORDER BY p.Score DESC, p.CreationDate ASC
            ) AS TagRank
        FROM Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT PostId, COUNT(*) AS TotalVotes
            FROM Votes
            GROUP BY PostId
        ) v ON v.PostId = p.Id
        LEFT JOIN (
            SELECT ParentId, COUNT(*) AS AnswerCount
            FROM Posts
            WHERE PostTypeId = 2
            GROUP BY ParentId
        ) a ON a.ParentId = p.Id
        WHERE p.PostTypeId = 1
    ),
    tag_stats AS (
        SELECT
            t.TagName,
            SUM(q.Score) AS TotalScore,
            SUM(q.AnswerCount) AS TotalAnswers,
            COUNT(DISTINCT q.Id) AS QuestionCount,
            AVG(q.VoteCount) AS AvgVotes,
            MIN(q.CreationDate) AS FirstSeen
        FROM question_posts q
        JOIN unnest(string_to_array(q.Tags, '><')) AS tag(tagname) ON tagname <> ''
        JOIN Tags t ON t.TagName = tag.tagname
        GROUP BY t.TagName
    ),
    top_tags AS (
        SELECT *
        FROM tag_stats
        ORDER BY TotalScore DESC, QuestionCount DESC
        LIMIT 20
    )
SELECT
    tt.TagName,
    tt.TotalScore,
    tt.TotalAnswers,
    tt.QuestionCount,
    tt.AvgVotes,
    tt.FirstSeen,
    qp.Id AS TopQuestionId,
    qp.Title AS TopQuestionTitle,
    qp.Score AS TopQuestionScore,
    qp.OwnerRep AS TopQuestionOwnerRep,
    qp.VoteCount AS TopQuestionVotes,
    qp.AnswerCount AS TopQuestionAnswerCount
FROM top_tags tt
JOIN LATERAL (
    SELECT
        qp2.Id,
        qp2.Title,
        qp2.Score,
        qp2.OwnerRep,
        qp2.VoteCount,
        qp2.AnswerCount
    FROM question_posts qp2
    WHERE qp2.Tags LIKE '%' || tt.TagName || '%'
    ORDER BY qp2.TagRank
    LIMIT 1
) qp ON true
ORDER BY tt.TotalScore DESC, tt.QuestionCount DESC, tt.TagName;