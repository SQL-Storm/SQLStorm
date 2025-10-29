-- {"query": "4220.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 988} 

WITH QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT bh.Id) AS RevisionCount,
        ROW_NUMBER() OVER(ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts AS p
    JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN PostHistory AS bh ON p.Id = bh.PostId AND bh.PostHistoryTypeId IN (4, 5, 7, 8)
    WHERE p.PostTypeId = 1 -- Questions
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate
),
AnswerDetails AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS AnswerCreationDate,
        p.Score AS AnswerScore,
        COUNT(c.Id) AS AnswerCommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AnswerUpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AnswerDownVoteCount,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts AS p
    JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2 -- Answers
    GROUP BY
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.Score
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.OwnerDisplayName AS QuestionOwner,
    qd.QuestionCreationDate,
    qd.QuestionScore,
    qd.QuestionViewCount,
    qd.AnswerCount AS TotalAnswers,
    qd.FavoriteCount AS Favorites,
    CASE WHEN qd.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
    qd.CommentCount AS QuestionCommentCount,
    qd.UpVoteCount AS QuestionUpVotes,
    qd.DownVoteCount AS QuestionDownVotes,
    qd.RevisionCount,
    ad.AnswerId AS BestAnswerId,
    ad.OwnerDisplayName AS BestAnswerOwner,
    ad.AnswerCreationDate AS BestAnswerCreationDate,
    ad.AnswerScore AS BestAnswerScore,
    ad.AnswerCommentCount AS BestAnswerCommentCount,
    ad.AnswerUpVoteCount AS BestAnswerUpVotes,
    ad.AnswerDownVoteCount AS BestAnswerDownVotes
FROM QuestionDetails AS qd
LEFT JOIN AnswerDetails AS ad ON qd.QuestionId = ad.QuestionId AND ad.AnswerRank = 1
WHERE qd.RowNum <= 1000 -- Limit for benchmarking
  AND qd.QuestionScore > 0
  AND qd.QuestionViewCount > 100
  AND (qd.ClosedDate IS NULL OR qd.ClosedDate < CURRENT_TIMESTAMP - INTERVAL '1 year')
  AND COALESCE(qd.OwnerDisplayName, 'Anonymous') <> 'Community'
ORDER BY qd.QuestionScore DESC;
