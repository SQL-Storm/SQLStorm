WITH RecentQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.CreationDate,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        COUNT(DISTINCT a.Id) AS AnswerCount
    FROM
        Posts q
        LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE
        q.PostTypeId = 1
        AND q.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY
    GROUP BY
        q.Id, q.CreationDate, q.Title, q.Tags, q.OwnerUserId, q.Score, q.ViewCount
),
AnswererStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(p.Score), 0) AS TotalAnswerScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
        LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionEdits AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDate
    FROM
        PostHistory ph
        INNER JOIN Posts p ON p.Id = ph.PostId AND p.PostTypeId = 1
    WHERE
        ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY
        ph.PostId
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        COUNT(*) AS DuplicateCount
    FROM
        PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY
        pl.PostId
),
TagInfo AS (
    SELECT
        p.Id AS PostId,
        -- convert tags like '<tag1><tag2>' into rows
        TRIM(tag) AS TagName
    FROM
        Posts p,
        LATERAL (
            SELECT regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag
        ) t
    WHERE
        p.PostTypeId = 1
        AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT
        TagName,
        COUNT(*) AS TagUseCount
    FROM TagInfo
    GROUP BY TagName
    HAVING COUNT(*) > 5
),
QuestionAnswerers AS (
    -- derive distinct answerer ids per question without arrays
    SELECT
        q.Id AS QuestionId,
        a.OwnerUserId AS AnswererId
    FROM Posts q
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, a.OwnerUserId
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.CreationDate,
    rq.OwnerUserId,
    u.DisplayName AS QuestionOwnerName,
    COALESCE(qe.EditCount, 0) AS EditCount,
    qe.LastEditDate,
    COALESCE(dl.DuplicateCount, 0) AS DuplicateOfCount,
    -- MainTags: aggregated top tags for the question
    (SELECT STRING_AGG(t.TagName, ', ' ORDER BY t.TagName)
     FROM TagInfo t
     JOIN TopTags tt ON tt.TagName = t.TagName
     WHERE t.PostId = rq.QuestionId
    ) AS MainTags,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = rq.QuestionId
        AND c.Score >= 5
    ) AS HighScoreComments,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = rq.QuestionId
        AND v.VoteTypeId = 5
    ) AS FavoriteCount,
    -- Average reputation of answerers
    (
        SELECT AVG(a_stats.Reputation)
        FROM (
            SELECT DISTINCT qa.AnswererId
            FROM QuestionAnswerers qa
            WHERE qa.QuestionId = rq.QuestionId
            AND qa.AnswererId IS NOT NULL
        ) distinct_a
        JOIN AnswererStats a_stats ON a_stats.UserId = distinct_a.AnswererId
    ) AS AvgAnswererReputation,
    -- Gold answerers names concatenated
    (
        SELECT STRING_AGG(a_stats.DisplayName, ', ' ORDER BY a_stats.DisplayName)
        FROM (
            SELECT DISTINCT qa.AnswererId
            FROM QuestionAnswerers qa
            WHERE qa.QuestionId = rq.QuestionId
            AND qa.AnswererId IS NOT NULL
        ) distinct_a
        JOIN AnswererStats a_stats ON a_stats.UserId = distinct_a.AnswererId
        WHERE a_stats.GoldBadges > 0
    ) AS GoldAnswerers,
    CASE 
        WHEN rq.Score > 10 AND COALESCE(qe.EditCount,0) > 2 THEN 'HOT & MODERATED'
        WHEN rq.Score > 10 THEN 'HOT'
        WHEN COALESCE(qe.EditCount,0) > 2 THEN 'MODERATED'
        ELSE 'NORMAL'
    END AS ActivityLabel
FROM
    RecentQuestions rq
    LEFT JOIN Users u ON rq.OwnerUserId = u.Id
    LEFT JOIN QuestionEdits qe ON rq.QuestionId = qe.PostId
    LEFT JOIN DuplicateLinks dl ON rq.QuestionId = dl.PostId
ORDER BY
    rq.Score DESC,
    COALESCE(qe.EditCount,0) DESC,
    rq.CreationDate DESC
LIMIT 30;