-- {"query": "33033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 931} 
WITH tagged_questions AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.CreationDate,
           p.ViewCount,
           p.Score,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_counts AS (
    SELECT TagName,
           COUNT(DISTINCT PostId) AS QuestionCount,
           COUNT(*) AS TagUsage
    FROM tagged_questions
    GROUP BY TagName
),
hot_tags AS (
    SELECT tc.TagName,
           tc.QuestionCount,
           tc.TagUsage,
           ROW_NUMBER() OVER (PARTITION BY tc.TagName ORDER BY QUE.CreationDate DESC) AS recent_question_rank,
           QUE.Title AS RecentQuestionTitle,
           QUE.CreationDate AS RecentQuestionDate,
           QUE.ViewCount AS RecentViewCount,
           QUE.Score AS RecentScore,
           QUE.AnswerCount AS RecentAnswerCount
    FROM tag_counts tc
    JOIN (
        SELECT p.*
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) QUE ON QUE.Tags LIKE '%' || tc.TagName || '%'
    WHERE QUE.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
top_tags AS (
    SELECT TagName,
           QuestionCount,
           TagUsage,
           recent_question_rank,
           RecentQuestionTitle,
           RecentQuestionDate,
           RecentViewCount,
           RecentScore,
           RecentAnswerCount,
           ROW_NUMBER() OVER (ORDER BY QuestionCount DESC, TagUsage DESC) AS popularity_rank
    FROM hot_tags
),
activity_stats AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ARRAY_AGG(c.Text) AS CommentsText,
        ARRAY_AGG(v.VoteTypeId) AS VoteTypes
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
most_recent_edit AS (
    SELECT ph.PostId, ph.CreationDate AS LastEditDate, ph.UserDisplayName AS LastEditor
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
    ORDER BY ph.CreationDate DESC
),
latest_edits AS (
    SELECT DISTINCT ON (ph.PostId) ph.PostId, ph.LastEditDate, ph.LastEditor
    FROM (
        SELECT p.Id AS PostId
        FROM Posts p
        WHERE p.PostTypeId IN (1, 2)
    ) p
    JOIN PostHistory ph ON ph.PostId = p.PostId
    ORDER BY ph.PostId, ph.CreationDate DESC
)
SELECT
    t.TagName,
    t.QuestionCount,
    t.TagUsage,
    t.RecentQuestionTitle,
    t.RecentQuestionDate,
    t.RecentViewCount,
    t.RecentScore,
    t.RecentAnswerCount,
    t.popularity_rank,
    a.PostId,
    a.Title,
    a.CreationDate,
    a.ViewCount,
    a.Score,
    a.AnswerCount,
    a.CommentCount,
    a.FavoriteCount,
    a.CommentsText,
    a.VoteTypes,
    le.LastEditDate,
    le.LastEditor
FROM top_tags t
LEFT JOIN activity_stats a ON a.PostId IN (
    SELECT Id FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'
)
LEFT JOIN latest_edits le ON le.PostId = a.PostId
ORDER BY t.popularity_rank, t.TagName;