-- {"query": "24066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1625} 

WITH questions AS (
    SELECT p.Id,
           p.Title,
           p.Tags,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.OwnerUserId,
           p.FavoriteCount,
           CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
      FROM Posts p
     WHERE p.PostTypeId = 1
       AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
       AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
),
dup AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           t1.Name AS LinkType
      FROM PostLinks pl
      JOIN LinkTypes t1 ON pl.LinkTypeId = t1.Id
     WHERE pl.LinkTypeId = 3                               -- duplicate
       AND pl.PostId IN (SELECT Id FROM questions)
),
answers AS (
    SELECT p.Id      AS AnswerId,
           p.ParentId AS QuestionId,
           p.Score,
           p.CreationDate AS AnswerCreationDate,
           ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
           COALESCE((SELECT COUNT(*) FROM Votes v
                       WHERE v.PostId = p.Id
                         AND v.VoteTypeId = 2), 0) AS UpVotes
      FROM Posts p
     WHERE p.PostTypeId = 2
),
question_stats AS (
    SELECT q.Id,
           q.Title,
           COUNT(a.AnswerId)                                      AS TotalAnswers,
           MAX(a.Score) FILTER (WHERE a.rn = 1)                    AS TopAnswerScore,
           SUM(a.UpVotes)                                         AS TotalUpVotes,
           AVG(a.Score)                                           AS AvgAnswerScore,
           COALESCE(dup.RelatedPostId, -1)                        AS DuplicateOf,
           CASE
               WHEN q.IsClosed = 1 THEN
                   (SELECT ph.Comment
                      FROM PostHistory ph
                     WHERE ph.PostId = q.Id
                       AND ph.PostHistoryTypeId = 10
                       AND ph.Comment IS NOT NULL
                     LIMIT 1)
               ELSE NULL
           END                                                   AS CloseReason
      FROM questions q
      LEFT JOIN answers a ON a.QuestionId = q.Id
      LEFT JOIN dup ON dup.PostId = q.Id
  GROUP BY q.Id, q.Title, q.IsClosed, dup.RelatedPostId
)
SELECT qs.Id,
       qs.Title,
       qs.TotalAnswers,
       qs.TopAnswerScore,
       qs.TotalUpVotes,
       qs.AvgAnswerScore,
       qs.DuplicateOf,
       qs.CloseReason,
       CONCAT('#', qs.Id::text, ': ', qs.Title) AS DisplayTitle
  FROM question_stats qs
 ORDER BY qs.TopAnswerScore DESC NULLS LAST,
          qs.TotalAnswers DESC
 LIMIT 100;
