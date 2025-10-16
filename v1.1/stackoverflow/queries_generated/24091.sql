-- {"query": "24091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4295} 

WITH
    /* Base set of questions */
    qposts AS (
        SELECT
            p.Id                      AS QId,
            p.Title                   AS QTitle,
            p.Tags                    AS QTags,
            p.OwnerUserId             AS QOwner,
            p.CreationDate            AS QCreated,
            array_length(regexp_split_to_array(p.Tags,'><'),1) AS TagCnt
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),

    /* Answers to those questions */
    answers AS (
        SELECT
            a.Id        AS AId,
            a.ParentId  AS QId,
            a.OwnerUserId AS AOwner,
            a.Score,
            a.CreationDate
        FROM Posts a
        WHERE a.PostTypeId = 2
    ),

    /* Rank each answer per question */
    ansranks AS (
        SELECT
            a.QId,
            a.AId,
            a.Score,
            RANK() OVER (PARTITION BY a.QId ORDER BY a.Score DESC) AS Rnk
        FROM answers a
    ),

    /* Up‑vote count per question */
    votes_up AS (
        SELECT
            v.PostId,
            COUNT(*) AS UpCnt
        FROM Votes v
        WHERE v.VoteTypeId = 2
        GROUP BY v.PostId
    ),

    /* Duplicate close votes per question */
    dupcloses AS (
        SELECT
            ph.PostId  AS QId,
            ph.Comment AS CloseReason,
            COUNT(*) AS CloseCnt
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId, ph.Comment
    ),

    /* Badge counts per user */
    user_badges AS (
        SELECT
            u.Id  AS UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),

    /* Similarity between questions based on shared tags */
    tag_sim AS (
        SELECT
            t1.QId AS Q1,
            t2.QId AS Q2,
            COUNT(*) AS SharedTags
        FROM (
            SELECT QId, unnest(string_to_array(Tag, '><')) AS Tag
            FROM qposts
        ) t1
        JOIN (
            SELECT QId, unnest(string_to_array(Tag, '><')) AS Tag
            FROM qposts
        ) t2
        ON t1.Tag = t2.Tag AND t1.QId < t2.QId
        GROUP BY t1.QId, t2.QId
    ),

    /* Count of answers on closed questions */
    closed_with_answers AS (
        SELECT
            q.QId,
            COUNT(a.AId) AS AnswerCnt
        FROM qposts q
        JOIN answers a ON a.QId = q.QId
        JOIN dupcloses dc ON dc.QId = q.QId
        GROUP BY q.QId
    )

SELECT
    q.QId,
    q.QTitle,
    q.TagCnt,
    q.QOwner,

    COALESCE(va.UpCnt,0)            AS UpVotes,
    COALESCE(dc.CloseCnt,0)         AS CloseVotes,
    COALESCE(dc.CloseReason,'NotClosed') AS CloseReason,

    /* Rank of the highest‑scoring answer (correlated subquery) */
    (SELECT MIN(Rnk) FROM ansranks ar WHERE ar.QId = q.QId) AS HighestScoreRank,

    COALESCE(ub.GoldCnt,0)          AS OwnerGold,
    COALESCE(ub.SilverCnt,0)        AS OwnerSilver,
    COALESCE(ub.BronzeCnt,0)        AS OwnerBronze,

    /* Owner type logic */
    CASE WHEN q.QOwner IS NULL THEN 'Community' ELSE 'User' END AS OwnerType,

    /* Weighted score combining up votes, gold badges and tag count */
    (COALESCE(va.UpCnt,0) + 3*COALESCE(ub.GoldCnt,0))::numeric / (q.TagCnt+1) AS WeightedScore

FROM qposts q
LEFT JOIN votes_up va             ON va.PostId = q.QId
LEFT JOIN dupcloses dc            ON dc.QId    = q.QId
LEFT JOIN user_badges ub           ON ub.UserId = q.QOwner

/* Only questions created after 2023 and either closed or having a non‑empty tag list */
WHERE q.QCreated >= '2023-01-01'
  AND (q.TagCnt > 0)

ORDER BY WeightedScore DESC, CloseVotes ASC
LIMIT 200

/* UNION ALL to also include all closed questions irrespective of other filters */
UNION ALL

SELECT
    q.QId,
    q.QTitle,
    q.TagCnt,
    q.QOwner,

    COALESCE(va.UpCnt,0)            AS UpVotes,
    COALESCE(dc.CloseCnt,0)         AS CloseVotes,
    COALESCE(dc.CloseReason,'NotClosed') AS CloseReason,

    (SELECT MIN(Rnk) FROM ansranks ar WHERE ar.QId = q.QId) AS HighestScoreRank,

    COALESCE(ub.GoldCnt,0)          AS OwnerGold,
    COALESCE(ub.SilverCnt,0)        AS OwnerSilver,
    COALESCE(ub.BronzeCnt,0)        AS OwnerBronze,

    CASE WHEN q.QOwner IS NULL THEN 'Community' ELSE 'User' END AS OwnerType,

    (COALESCE(va.UpCnt,0) + 3*COALESCE(ub.GoldCnt,0))::numeric / (q.TagCnt+1) AS WeightedScore

FROM qposts q
LEFT JOIN votes_up va             ON va.PostId = q.QId
LEFT JOIN dupcloses dc            ON dc.QId    = q.QId
LEFT JOIN user_badges ub           ON ub.UserId = q.QOwner

WHERE EXISTS (SELECT 1 FROM dupcloses dc2 WHERE dc2.QId = q.QId)

ORDER BY WeightedScore DESC, CloseVotes DESC
LIMIT 100;
