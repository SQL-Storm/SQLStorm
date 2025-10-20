-- {"query": "35059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 599} 
WITH RecentEdits AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(*) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6)
        AND ph.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY
        ph.PostId
),
TopTags AS (
    SELECT
        t.TagName,
        SUM(t.Count) AS TotalCount
    FROM
        Tags t
    GROUP BY
        t.TagName
    ORDER BY
        TotalCount DESC
    LIMIT 50
),
Questions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '180 days'
),
QuestionTag AS (
    SELECT
        q.Id AS PostId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
    FROM
        Questions q
)
SELECT
    q.Id AS QuestionId,
    u.DisplayName AS Owner,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    te.TagName,
    COALESCE(re.EditCount, 0) AS EditCount,
    COALESCE(re.DistinctEditors, 0) AS DistinctEditors,
    (
        SELECT COUNT(*)
        FROM Posts a
        WHERE a.ParentId = q.Id
          AND a.PostTypeId = 2
    ) AS AnswerCount,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = q.Id
    ) AS CommentCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = q.Id
          AND v.VoteTypeId = 2
    ) AS Upvotes,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = q.Id
          AND v.VoteTypeId = 3
    ) AS Downvotes
FROM
    Questions q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    INNER JOIN QuestionTag qt ON qt.PostId = q.Id
    INNER JOIN TopTags te ON te.TagName = qt.TagName
    LEFT JOIN RecentEdits re ON re.PostId = q.Id
WHERE
    q.Score >= 5
    AND q.ViewCount >= 1000
ORDER BY
    COALESCE(re.EditCount, 0) DESC,
    q.ViewCount DESC
LIMIT 100;