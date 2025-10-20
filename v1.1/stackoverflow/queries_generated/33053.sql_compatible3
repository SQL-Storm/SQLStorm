WITH TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        c.ArticleType,
        c.Excerpt,
        c.ViewCount AS TagViewCount,
        c.VoteCount,
        c.CommentCount AS TagCommentCount
    FROM Tags t
    LEFT JOIN (
        SELECT 
            p.Id AS TagId,
            p.ContentLicense,
            p.Title AS ArticleType,
            p.Body AS Excerpt,
            p.ViewCount,
            tag_counts.VoteCount,
            (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS CommentCount
        FROM Posts p
        LEFT JOIN (
            SELECT tt.TagName AS tagname_inner, COUNT(*) AS VoteCount
            FROM Posts pp,
            LATERAL (
                SELECT elem AS TagNameElem
                FROM UNNEST(STRING_TO_ARRAY(SUBSTR(pp.Tags, 2, LENGTH(pp.Tags)-2), '><')) AS t(elem)
            ) expanded
            JOIN Tags tt ON tt.TagName = TRIM(expanded.TagNameElem)
            GROUP BY tt.TagName
        ) tag_counts ON tag_counts.tagname_inner = ANY (
            SELECT TRIM(elem) FROM UNNEST(STRING_TO_ARRAY(SUBSTR(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS t(elem)
        )
        WHERE p.PostTypeId IN (4, 5)
    ) c ON t.Id = c.TagId
)
SELECT 
    tq.QuestionId,
    tq.Title,
    tq.Tags,
    tq.CreationDate,
    tq.QuestionScore,
    tq.ViewCount,
    tq.OwnerName,
    tq.OwnerReputation,
    tq.AnswerCount,
    tq.CommentCount,
    tq.LinkCount,
    tt.TagName,
    tt.Count AS TagUsageCount,
    tt.ArticleType,
    tt.Excerpt AS TagExcerpt,
    tt.TagViewCount,
    tt.VoteCount AS TagVoteCount,
    tt.TagCommentCount
FROM TopQuestions tq
LEFT JOIN TopTags tt 
  ON EXISTS (
      SELECT 1
      FROM UNNEST(STRING_TO_ARRAY(SUBSTR(tq.Tags, 2, LENGTH(tq.Tags)-2), '><')) AS t(elem)
      WHERE TRIM(t.elem) = tt.TagName
  )
ORDER BY tq.CreationDate DESC
LIMIT 100;