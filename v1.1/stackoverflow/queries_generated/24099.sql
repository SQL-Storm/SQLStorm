-- {"query": "24099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2386} 

WITH
    -- 1️⃣ Posts that are questions
    question_posts AS (
        SELECT p.Id,
               p.OwnerUserId,
               p.CreationDate,
               p.Score,
               p.ViewCount,
               p.Title,
               p.Tags,
               CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END          AS IsClosed,
               DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP)           AS DaysSinceCreation
        FROM   Posts p
        WHERE  p.PostTypeId = 1
              AND (
                  p.Title  ILIKE '%database%'            -- long‑string predicate
                  OR p.Tags ILIKE '%[%sql%]%'           -- embedded regex pattern
              )
    ),

    -- 2️⃣ Most recent close event for each question
    closes AS (
        SELECT ph.PostId,
               MAX(ph.CreationDate) AS LastCloseDate
        FROM   PostHistory ph
               JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        WHERE  pht.Name ILIKE '%Close%'           -- correlated on name
        GROUP  BY ph.PostId
    ),

    -- 3️⃣ Reputation ranking of users (window function)
    user_rank AS (
        SELECT u.Id,
               u.Reputation,
               RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank
        FROM   Users u
    ),

    -- 4️⃣ Tags split into individual strings
    tag_counts AS (
        SELECT p.Id   AS PostId,
               LTRIM(RTRIM(tag, ']'), '[') AS Tag
        FROM   Posts p
               CROSS JOIN LATERAL
               unnest(string_to_array(REGEXP_REPLACE(p.Tags, '[\[\]]','', 'g'), '> <')) AS tag
        WHERE  p.PostTypeId = 1
    ),

    -- 5️⃣ Posts that are answers
    answer_posts AS (
        SELECT p.Id,
               p.OwnerUserId,
               p.Score,
               p.Title
        FROM   Posts p
        WHERE  p.PostTypeId = 2
    ),

    -- 6️⃣ Vote & comment aggregates for answers
    answer_details AS (
        SELECT a.Id,
               (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS UpVotes,
               (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) AS DownVotes,
               (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS CommentCount
        FROM   answer_posts a
    )

SELECT
        qp.Id            AS PostId,
        qp.Title,
        qp.Score,
        qp.ViewCount,
        CASE WHEN qp.IsClosed = 1 THEN 'Closed' ELSE 'Open' END AS Status,
        qp.DaysSinceCreation,
        ur.Reputation,
        ur.RepRank,
        ARRAY_AGG(DISTINCT tc.Tag ORDER BY tc.Tag) AS Tags,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qp.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qp.Id AND v.VoteTypeId = 3) AS DownVotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qp.Id) AS CommentCount,
        closes.LastCloseDate
FROM   question_posts qp
       LEFT JOIN closes       ON closes.PostId      = qp.Id
       LEFT JOIN user_rank    ON user_rank.Id      = qp.OwnerUserId
       LEFT JOIN tag_counts   ON tag_counts.PostId  = qp.Id
GROUP  BY qp.Id, qp.Title, qp.Score, qp.ViewCount, qp.Status, qp.DaysSinceCreation,
          ur.Reputation, ur.RepRank, closes.LastCloseDate
UNION ALL
SELECT
        a.Id            AS PostId,
        a.Title,
        a.Score,
        NULL                                  AS ViewCount,
        NULL                                  AS Status,
        NULL                                  AS DaysSinceCreation,
        ur.Reputation,
        ur.RepRank,
        NULL::text[]/* tags are irrelevant for answers */,
        ad.UpVotes,
        ad.DownVotes,
        ad.CommentCount,
        NULL::timestamp/* close date irrelevant for answers */
FROM   answer_posts a
       LEFT JOIN user_rank     ON user_rank.Id      = a.OwnerUserId
       LEFT JOIN answer_details ON answer_details.Id = a.Id
WHERE  NOT EXISTS (SELECT 1 FROM question_posts qp WHERE qp.Id = a.Id)   -- avoid duplicate
ORDER  BY PostId
LIMIT  200;
