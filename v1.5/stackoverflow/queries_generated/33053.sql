-- {"query": "33053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 484} 
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
    WHERE p.PostTypeId = 1 -- Questions
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
            (SELECT COUNT(*) FROM Posts WHERE Tags @> ARRAY[t.TagName]) AS VoteCount,
            (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS CommentCount
        FROM Posts p
        WHERE p.PostTypeId IN (4, 5) -- Tag Wiki Excerpts and Tag Wikis
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
LEFT JOIN TopTags tt ON array_position(string_to_array(substr(tq.Tags, 2, length(tq.Tags)-2), '><'), tt.TagName) IS NOT NULL
ORDER BY tq.CreationDate DESC
LIMIT 100;