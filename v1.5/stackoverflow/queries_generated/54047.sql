-- {"query": "54047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1641} 

WITH
    question_votes AS (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
        FROM Votes
        GROUP BY PostId
    ),
    question_links AS (
        SELECT
            PostId,
            COUNT(*) AS link_count
        FROM PostLinks
        GROUP BY PostId
    ),
    question_tags AS (
        SELECT
            PostId,
            regexp_split_to_array(Tags, E'<>') AS tag_array
        FROM Posts
        WHERE PostTypeId = 1
    ),
    first_last_edits AS (
        SELECT
            ph.PostId,
            MIN(ph.CreationDate) AS first_edit,
            MAX(ph.CreationDate) AS last_edit
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId NOT IN (10,11,12,13,14,15,19,20,35,36)
        GROUP BY ph.PostId
    )
SELECT
    q.Id                           AS QuestionId,
    q.Title                        AS QuestionTitle,
    q.Tags                         AS RawTags,
    q.Score                        AS QuestionScore,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.Views,
    q.CreationDate,
    q.LastActivityDate,
    u.Id                           AS UserId,
    u.DisplayName,
    u.Reputation,
    array_to_string(qt.tag_array, ', ') AS ParsedTags,
    ql.link_count,
    qv.upvotes,
    qv.downvotes,
    EXTRACT(EPOCH FROM (q.LastActivityDate - q.CreationDate)) AS ActivitySeconds,
    (SELECT string_agg(b.Name, ', ') FROM Badges b WHERE b.UserId = u.Id) AS BadgeList,
    el.first_edit,
    el.last_edit,
    ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.CreationDate ASC) AS Rank
FROM Posts q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN question_votes qv ON qv.PostId = q.Id
LEFT JOIN question_links ql ON ql.PostId = q.Id
LEFT JOIN question_tags qt ON qt.PostId = q.Id
LEFT JOIN first_last_edits el ON el.PostId = q.Id
WHERE q.PostTypeId = 1
ORDER BY q.Score DESC, q.CreationDate ASC
LIMIT 1000;
