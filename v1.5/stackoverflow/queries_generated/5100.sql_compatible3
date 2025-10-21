WITH RecentQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.CreationDate,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        ARRAY_AGG(DISTINCT a.OwnerUserId) AS AnswererIds
    FROM
        Posts q
        LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE
        q.PostTypeId = 1
        AND q.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY)
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
        LEFT JOIN Badges b ON b.UserId = u.Id
            AND b.Date > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
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
        UNNEST(
            STRING_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2),
                '><'
            )
        ) AS TagName
    FROM
        Posts p
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
    (
        SELECT ARRAY_AGG(t.TagName)
        FROM (
            SELECT t.TagName
            FROM TagInfo t
            WHERE t.PostId = rq.QuestionId
            AND t.TagName IN (
                SELECT TagName FROM TopTags
            )
            ORDER BY t.TagName
        ) AS t
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
    (
        SELECT AVG(a_stats.Reputation)
        FROM UNNEST(rq.AnswererIds) AS aid
        JOIN AnswererStats a_stats ON a_stats.UserId = aid
    ) AS AvgAnswererReputation,
    (
        SELECT STRING_AGG(a_stats.DisplayName, ', ')
        FROM UNNEST(rq.AnswererIds) AS aid
        JOIN AnswererStats a_stats ON a_stats.UserId = aid
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