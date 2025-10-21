-- {"query": "24026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4648} 
WITH
QuestionData AS (
    SELECT
        q.Id                                      AS QuestionId,
        q.Title                                   AS Title,
        q.Tags                                    AS Tags,
        q.CreationDate                            AS QuestionCreation,
        COALESCE(u.DisplayName, 'anon')           AS OwnerName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS QuestionUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS QuestionDownVotes,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id) AS AnswerCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.VoteTypeId)
            OVER (PARTITION BY q.Id)           AS MedianVoteType,
        COALESCE(ph.CloseVotes,0)                AS DuplicateCloseVotes,
        COALESCE(ph.DeleteVotes,0)               AS DeleteVotes
    FROM
        Posts q
        LEFT JOIN Users u ON u.Id = q.OwnerUserId
        LEFT JOIN Votes v ON v.PostId = q.Id
        LEFT JOIN (
            SELECT
                ph.PostId,
                SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
                SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteVotes
            FROM PostHistory ph
            GROUP BY ph.PostId
        ) ph ON ph.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.CreationDate, q.OwnerUserId, u.DisplayName,
             ph.CloseVotes, ph.DeleteVotes
),
TagData AS (
    SELECT
        t.Id                                AS TagId,
        t.TagName                           AS TagName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)   AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)   AS TotalDownVotes,
        MIN(p.CreationDate)                 AS FirstSeen,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM
        Tags t
        JOIN Posts p ON p.Tags IS NOT NULL AND p.Tags LIKE '%' || t.TagName || '%'
        JOIN Votes v ON v.PostId = p.Id
    GROUP BY t.Id, t.TagName
)
SELECT
    'Q'||q.QuestionId  AS UniqueId,
    q.Title             AS EntityName,
    COALESCE(q.AnswerCount,0)      AS Metric1,
    q.QuestionUpVotes  AS Metric2,
    q.QuestionDownVotes AS Metric3,
    CAST(q.QuestionCreation AS DATE) AS Metric4,
    CASE WHEN q.DuplicateCloseVotes > 10 THEN 'Critical' ELSE 'OK' END AS Status
FROM
    QuestionData q
WHERE
    q.AnswerCount > 0
UNION ALL
SELECT
    'T'||t.TagId            AS UniqueId,
    t.TagName               AS EntityName,
    t.TotalUpVotes          AS Metric1,
    t.TotalDownVotes        AS Metric2,
    NULL                    AS Metric3,
    t.FirstSeen             AS Metric4,
    CASE WHEN t.TagRank <= 5 THEN 'Hot' ELSE 'Cold' END AS Status
FROM
    TagData t
ORDER BY
    Metric4 DESC NULLS LAST
LIMIT 200;