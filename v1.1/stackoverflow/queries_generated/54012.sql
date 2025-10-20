-- {"query": "54012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2665} 

WITH
    recent_questions AS (
        SELECT
            Id,
            Title,
            Score,
            ViewCount,
            CreationDate,
            OwnerUserId
        FROM Posts
        WHERE PostTypeId = 1
          AND CreationDate >= DATE_SUB(CURRENT_DATE, INTERVAL '30 DAY')
    ),
    answer_stats AS (
        SELECT
            ParentId AS QuestionId,
            COUNT(*) AS AnswerCount,
            AVG(
                TIMESTAMPDIFF(
                    SECOND,
                    CreationDate,
                    (SELECT MIN(CreationDate)
                     FROM Posts AS a
                     WHERE a.ParentId = ParentId
                       AND a.PostTypeId = 2)
                )
            ) AS AvgAnswerTimeSec
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ),
    vote_counts AS (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount
        FROM Votes
        GROUP BY PostId
    ),
    comment_counts AS (
        SELECT
            PostId,
            COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ),
    link_stats AS (
        SELECT
            PostId,
            SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCount,
            SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount
        FROM PostLinks
        GROUP BY PostId
    ),
    closure_info AS (
        SELECT
            PostId,
            MIN(CreationDate) AS ClosedDate,
            MAX(Comment) AS CloseReason
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        GROUP BY PostId
    )
SELECT
    rq.Id,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.CreationDate,
    u.Reputation,
    u.DisplayName,
    ASV.AnswerCount,
    ASV.AvgAnswerTimeSec,
    VC.UpVotes,
    VC.DownVotes,
    VC.FavoriteCount,
    CC.CommentCount,
    LS.LinkedCount,
    LS.DuplicateCount,
    COALESCE(CI.ClosedDate, 'Open')          AS Status,
    COALESCE(CI.CloseReason, '')           AS CloseReason
FROM recent_questions rq
LEFT JOIN Users u ON u.Id = rq.OwnerUserId
LEFT JOIN answer_stats ASV ON ASV.QuestionId = rq.Id
LEFT JOIN vote_counts VC ON VC.PostId = rq.Id
LEFT JOIN comment_counts CC ON CC.PostId = rq.Id
LEFT JOIN link_stats LS ON LS.PostId = rq.Id
LEFT JOIN closure_info CI ON CI.PostId = rq.Id
ORDER BY rq.ViewCount DESC,
         rq.Score DESC,
         VC.UpVotes DESC
LIMIT 10;
