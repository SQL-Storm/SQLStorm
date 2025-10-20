-- {"query": "9014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 4672} 

WITH YearlyTopQuestions AS (
    SELECT
        p.Id                 AS QuestionId,
        p.Title,
        p.OwnerUserId,
        u.Reputation,
        YEAR(p.CreationDate) AS Year,
        ROW_NUMBER() OVER (
            PARTITION BY YEAR(p.CreationDate)
            ORDER BY p.Score DESC
        )                  AS YearRank,
        COUNT(c.Id) OVER (
            PARTITION BY p.Id
        )                  AS CommentCount
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
),
BadgeAgg AS (
    SELECT
        UserId,
        COUNT(*)     AS BadgeCount,
        MAX(Date)    AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
VoteNet AS (
    SELECT
        PostId,
        SUM(
          CASE
            WHEN VoteTypeId = 2 THEN  1
            WHEN VoteTypeId = 3 THEN -1
            ELSE 0
          END
        )            AS NetVotes
    FROM Votes
    GROUP BY PostId
),
CorrelatedAnswers AS (
    SELECT
        q.QuestionId,
        (
          SELECT COUNT(*)
          FROM Posts a
          WHERE a.ParentId = q.QuestionId
            AND a.Score > q.Reputation/NULLIF(a.Score,0)
        )              AS HighScoringAnswers
    FROM YearlyTopQuestions q
),
QuestionActivity AS (
    SELECT
        PostId,
        MAX(CreationDate) AS LastHistDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6)
    GROUP BY PostId
)
SELECT
    yq.Year,
    yq.YearRank,
    LEFT(yq.Title,50)
      + CASE WHEN LEN(yq.Title)>50 THEN '...' ELSE '' END        AS TruncTitle,
    CONCAT('#', yq.QuestionId, '(', COALESCE(vn.NetVotes,0), ' votes)') AS QInfo,
    COALESCE(ba.BadgeCount,0)                                 AS BadgeCount,
    COALESCE(CONVERT(varchar(10), ba.LastBadgeDate, 23),'1970-01-01') AS LastBadge,
    COALESCE(qc.HighScoringAnswers,0)                         AS HiAns,
    yq.CommentCount,
    CASE
      WHEN u.Location IS NULL
        OR LTRIM(RTRIM(u.Location)) = ''
      THEN 'NoLoc'
      ELSE LEFT(u.Location,15)
    END                                                        AS LocLabel,
    qa.LastHistDate
FROM YearlyTopQuestions yq
LEFT JOIN BadgeAgg ba
  ON yq.OwnerUserId = ba.UserId
LEFT JOIN VoteNet vn
  ON yq.QuestionId = vn.PostId
LEFT JOIN CorrelatedAnswers qc
  ON yq.QuestionId = qc.QuestionId
LEFT JOIN Users u
  ON yq.OwnerUserId = u.Id
LEFT JOIN QuestionActivity qa
  ON yq.QuestionId = qa.PostId
WHERE yq.Reputation > (SELECT AVG(Reputation) FROM Users)

UNION ALL

SELECT
    YEAR(GETDATE()),
   -1,
    'NEGQ',
    'negative-score',
     0,
    CONVERT(varchar(10),GETDATE(),23),
     0,
     0,
    'NoLoc',
    GETDATE()
WHERE EXISTS (SELECT 1 FROM Posts p2 WHERE p2.Score < 0)

EXCEPT

SELECT
    y.Year,
    y.YearRank,
    LEFT(y.Title,50)
      + CASE WHEN LEN(y.Title)>50 THEN '...' ELSE '' END,
    CONCAT('#', y.QuestionId, '(', COALESCE(vn2.NetVotes,0), ' votes)'),
    COALESCE(ba2.BadgeCount,0),
    CONVERT(varchar(10), ba2.LastBadgeDate,23),
    qc2.HighScoringAnswers,
    y.CommentCount,
    CASE
      WHEN u2.Location IS NULL
        OR LTRIM(RTRIM(u2.Location)) = ''
      THEN 'NoLoc'
      ELSE LEFT(u2.Location,15)
    END,
    qa2.LastHistDate
FROM YearlyTopQuestions y
JOIN VoteNet vn2
  ON y.QuestionId = vn2.PostId
JOIN BadgeAgg ba2
  ON y.OwnerUserId = ba2.UserId
JOIN CorrelatedAnswers qc2
  ON y.QuestionId = qc2.QuestionId
JOIN Users u2
  ON y.OwnerUserId = u2.Id
JOIN QuestionActivity qa2
  ON y.QuestionId = qa2.PostId
WHERE y.YearRank > 5

ORDER BY Year, YearRank, BadgeCount DESC;
