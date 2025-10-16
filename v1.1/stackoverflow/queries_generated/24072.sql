-- {"query": "24072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3938} 

WITH question AS (
    SELECT p.Id        AS QId,
           p.Title,
           p.Tags,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           COALESCE(u.Reputation,0)          AS OwnerRep,
           u.DisplayName AS OwnerName,
           u.Id          AS OwnerId,
           COALESCE(dup.cnt,0)                AS DuplicateCount
    FROM   Posts p
    LEFT   JOIN Users u       ON u.Id = p.OwnerUserId
    LEFT   JOIN (
        SELECT PostId, COUNT(*) AS cnt
        FROM   PostLinks
        WHERE  LinkTypeId = 3
        GROUP  BY PostId
    ) dup ON dup.PostId = p.Id
    WHERE  p.PostTypeId = 1
),

vote_cnt AS (
    SELECT  VoteTypeId,
            PostId,
            COUNT(*) AS cnt
    FROM    Votes
    WHERE   PostId IN (SELECT QId FROM question)
    GROUP BY VoteTypeId, PostId
),

vote_agg AS (
    SELECT  PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN cnt ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN cnt ELSE 0 END) AS DownVotes,
            STRING_AGG(CAST(VoteTypeId AS VARCHAR), ', ')          AS VoteList
    FROM    vote_cnt
    GROUP   BY PostId
),

tag_cnt AS (
    SELECT  QId,
            array_length(
                regexp_split_to_array(substring(Tags,2, length(Tags)-2), '><'),1
            ) AS TagCount
    FROM    question
),

joined AS (
    SELECT  q.*,
            v.UpVotes,
            v.DownVotes,
            t.TagCount
    FROM    question q
    LEFT JOIN vote_agg v ON v.PostId = q.QId
    LEFT JOIN tag_cnt t ON t.QId = q.QId
),

rowed AS (
    SELECT  j.*,
            ROW_NUMBER() OVER (
                ORDER BY j.Score DESC, j.AnswerCount DESC, j.ViewCount DESC
            ) AS RN
    FROM    joined j
)

SELECT  r.QId,
        r.Title,
        r.Tags,
        r.Score,
        r.ViewCount,
        r.AnswerCount,
        r.TagCount,
        r.OwnerName,
        r.OwnerRep,
        r.DuplicateCount,
        r.UpVotes,
        r.DownVotes,
        CASE
            WHEN r.Score > 100 AND r.ViewCount > 20000 THEN 'Epic'
            WHEN r.Score > 20  AND r.TagCount   > 4    THEN 'Expert'
            ELSE                           'Regular'
        END                 AS Category,
        (SELECT COUNT(*)
           FROM Posts p2
          WHERE p2.OwnerUserId = r.OwnerId
            AND p2.PostTypeId = 1
            AND p2.Score > 0)      AS OwnerHighScoreQCount
FROM    rowed r
WHERE   r.RN <= 20

UNION ALL

SELECT  r.QId,
        r.Title,
        r.Tags,
        r.Score,
        r.ViewCount,
        r.AnswerCount,
        r.TagCount,
        r.OwnerName,
        r.OwnerRep,
        r.DuplicateCount,
        r.UpVotes,
        r.DownVotes,
        CASE
            WHEN r.Score > 100 AND r.ViewCount > 20000 THEN 'Epic'
            WHEN r.Score > 20  AND r.TagCount   > 4    THEN 'Expert'
            ELSE                           'Regular'
        END                 AS Category,
        (SELECT COUNT(*)
           FROM Posts p2
          WHERE p2.OwnerUserId = r.OwnerId
            AND p2.PostTypeId = 1
            AND p2.Score > 0)      AS OwnerHighScoreQCount
FROM    rowed r
WHERE   r.DuplicateCount > 0
  AND   r.Score < 15

ORDER BY 4 DESC, 7 DESC;
