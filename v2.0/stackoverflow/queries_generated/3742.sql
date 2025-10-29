-- {"query": "3742.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2613} 

WITH
    q AS (
        SELECT
            p.Id                         AS QuestionId,
            p.OwnerUserId                AS OwnerUserId,
            p.Score                      AS QuestionScore,
            p.CreationDate,
            p.Title,
            p.Tags,
            COALESCE(p.FavoriteCount,0)  AS FavCnt,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_q
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    a AS (
        SELECT
            p.Id                         AS AnswerId,
            p.OwnerUserId                AS OwnerUserId,
            p.ParentId                   AS QuestionId,
            p.Score                      AS AnswerScore,
            p.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_a
        FROM Posts p
        WHERE p.PostTypeId = 2
    ),
    u AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate               AS UserCreation,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
            COALESCE(b.BadgeCount,0)    AS BadgeCount,
            COALESCE(v.VoteCount,0)     AS TotalVotes,
            COALESCE(c.CommentCount,0)  AS CommentCount
        FROM Users u
        LEFT JOIN (SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId) b   ON b.UserId = u.Id
        LEFT JOIN (SELECT UserId, COUNT(*) AS VoteCount   FROM Votes   GROUP BY UserId) v   ON v.UserId = u.Id
        LEFT JOIN (SELECT UserId, COUNT(*) AS CommentCount FROM Comments GROUP BY UserId) c ON c.UserId = u.Id
    ),
    tag_stats AS (
        SELECT
            t.TagName,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum
        FROM Tags t
        LEFT JOIN LATERAL (
            SELECT Id, PostTypeId, Score, Tags
            FROM Posts
            WHERE Tags IS NOT NULL
              AND POSITION('<' || t.TagName || '>' IN Tags) > 0
        ) p ON true
        GROUP BY t.TagName
    )
SELECT
    u.Id                                     AS UserId,
    u.DisplayName,
    u.Reputation,
    u.NetVotes,
    u.BadgeCount,
    u.TotalVotes,
    u.CommentCount,
    q.QuestionId,
    q.Title,
    q.QuestionScore,
    q.FavCnt,
    a.AnswerId,
    a.AnswerScore,
    COALESCE(ts.QuestionCount,0)             AS TagQuestionCount,
    COALESCE(ts.AnswerCount,0)               AS TagAnswerCount,
    CASE
        WHEN q.Tags IS NULL THEN NULL
        ELSE array_to_string(
                 ARRAY(
                     SELECT REPLACE(REPLACE(tag,'<',''),'>','')
                     FROM UNNEST(string_to_array(substr(q.Tags,2,length(q.Tags)-2),'><')) AS tag
                 ), ',')
    END                                      AS CleanTagList,
    EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.PostId = q.QuestionId
          AND ph.PostHistoryTypeId = 10        -- Closed
          AND ph.Comment = '101'               -- Duplicate
    )                                        AS IsDuplicateClosed
FROM u
LEFT JOIN q ON q.OwnerUserId = u.Id AND q.rn_q = 1
LEFT JOIN a ON a.OwnerUserId = u.Id AND a.rn_a = 1
LEFT JOIN tag_stats ts ON ts.TagName = (
        SELECT REPLACE(REPLACE(tag,'<',''),'>','')
        FROM UNNEST(string_to_array(substr(q.Tags,2,length(q.Tags)-2),'><')) AS tag
        LIMIT 1
    )
WHERE u.Reputation > 1000
  AND (u.BadgeCount > 5 OR u.TotalVotes > 20)
  AND (q.QuestionId IS NOT NULL OR a.AnswerId IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM Users du WHERE du.Id = u.Id AND du.EmailHash IS NULL)

UNION ALL

SELECT
    u2.Id,
    u2.DisplayName,
    u2.Reputation,
    COALESCE(u2.UpVotes,0) - COALESCE(u2.DownVotes,0) AS NetVotes,
    COALESCE(b2.BadgeCount,0) AS BadgeCount,
    COALESCE(v2.VoteCount,0)  AS TotalVotes,
    COALESCE(c2.CommentCount,0) AS CommentCount,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM Users u2
LEFT JOIN (SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId) b2 ON b2.UserId = u2.Id
LEFT JOIN (SELECT UserId, COUNT(*) AS VoteCount FROM Votes GROUP BY UserId) v2 ON v2.UserId = u2.Id
LEFT JOIN (SELECT UserId, COUNT(*) AS CommentCount FROM Comments GROUP BY UserId) c2 ON c2.UserId = u2.Id
WHERE u2.Reputation BETWEEN 500 AND 999
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u2.Id AND p.PostTypeId = 1)

ORDER BY Reputation DESC NULLS LAST, UserId ASC
LIMIT 100;
