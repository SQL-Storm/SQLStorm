WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        u.Reputation,
        u.Id AS OwnerId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        EXISTS (
            SELECT 1
            FROM Votes v
            WHERE v.PostId = p.Id
              AND v.VoteTypeId = 2
        ) AS HasUpvote
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.AnswerCount, u.Reputation, u.Id
), TopAnswerByQuestion AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS Rn
    FROM Posts a
    WHERE a.PostTypeId = 2
), TagDeciles AS (
    SELECT
        jt.tag AS TagName,
        COUNT(*) AS TagUsage,
        NTILE(10) OVER (ORDER BY COUNT(*) DESC) AS Decile
    FROM Posts p,
         LATERAL (
           SELECT trim(both ' ' FROM regexp_split_to_table(regexp_replace(p.Tags, '[<>]', '', 'g'), ',')) AS tag
         ) jt
    GROUP BY jt.tag
), DuplicateLinks AS (
    SELECT p.Id AS DuplicateOf
    FROM PostLinks p
    WHERE p.LinkTypeId = 3
), CloseStatuses AS (
    SELECT
        ph.PostId,
        CASE
            WHEN ph.Text IS NOT NULL AND ph.Text <> '' AND ph.Text ~ '"CloseReasonId"[[:space:]]*:[[:space:]]*"[0-9]+"' THEN cr.Name
            ELSE 'Open'
        END AS Status
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr
           ON (
                -- extract digits from the first occurrence of "CloseReasonId": "...\"CloseReasonId\":\"123\"..."
                -- use regexp_replace to remove everything except digits; compatible cast to text is avoided
                regexp_replace(
                    regexp_replace(
                        substring(ph.Text FROM '"CloseReasonId"[[:space:]]*:[[:space:]]*"[0-9]+"' ),
                        '[^0-9]',
                        '',
                        'g'
                    ),
                    '[^0-9]',
                    '',
                    'g'
                )
                = CAST(cr.Id AS VARCHAR)
              )
    WHERE ph.PostHistoryTypeId = 10
)
SELECT
    rq.Id AS QuestionId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.AnswerCount,
    COALESCE(rq.OwnerId, -1) AS OwnerId,
    COALESCE(rq.Reputation, 0) AS OwnerReputation,
    rq.CommentCount,
    rq.HasUpvote,
    td.Decile AS TagPopularity,
    CASE WHEN dl.DuplicateOf IS NOT NULL THEN 1 ELSE 0 END AS IsDuplicate,
    cs.Status AS CloseStatus
FROM RecentQuestions rq
LEFT JOIN TopAnswerByQuestion ta
       ON ta.ParentId = rq.Id
      AND ta.Rn = 1
LEFT JOIN TagDeciles td
       ON td.TagName = ANY (regexp_split_to_array(regexp_replace(rq.Tags, '[<>]', '', 'g'), ','))
LEFT JOIN DuplicateLinks dl
       ON dl.DuplicateOf = rq.Id
LEFT JOIN CloseStatuses cs
       ON cs.PostId = rq.Id
WHERE rq.AnswerCount > 0
  AND rq.Score > 5
  AND (rq.Tags LIKE '%[java]%' OR rq.Tags LIKE '%[c#]%')
GROUP BY
    rq.Id,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.AnswerCount,
    rq.OwnerId,
    rq.Reputation,
    rq.CommentCount,
    rq.HasUpvote,
    td.Decile,
    dl.DuplicateOf,
    cs.Status
ORDER BY rq.Score DESC, rq.CreationDate ASC
LIMIT 100;