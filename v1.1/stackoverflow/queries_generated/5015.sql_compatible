WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),

QuestionCTE AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.ViewCount,
        -- replace PostgreSQL string_to_array/array_length with generic parsing using regexp_split_to_table style is not portable;
        -- emulate tag count by counting occurrences of '><' plus 1 when tags not empty
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
            ELSE (length(p.Tags) - length(replace(p.Tags, '><', '')))/length('><') + 1
        END AS TagCount,
        COALESCE(p.ClosedDate, TIMESTAMP '1970-01-01 00:00:00') AS ClosedDate,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),

AnswerCTE AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate
    FROM Posts a
    WHERE a.PostTypeId = 2
),

VoteAggs AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.UserId END) AS Favorites
    FROM Votes v
    GROUP BY v.PostId
),

RecentComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS RecentComments
    FROM Comments c
    WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY c.PostId
),

LongestCloseReason AS (
    SELECT
        c.Comment AS CloseReasonId,
        MAX(LENGTH(cr.Name)) AS MaxCloseReasonLen
    FROM PostHistory c
    JOIN CloseReasonTypes cr ON CAST(c.Comment AS INTEGER) = cr.Id
    WHERE c.PostHistoryTypeId = 10
    GROUP BY c.Comment
)

SELECT
    q.QuestionId,
    u.DisplayName AS QuestionAuthor,
    qb.TotalBadges,
    qb.GoldBadges,
    qb.SilverBadges,
    qb.BronzeBadges,
    q.Title,
    q.QuestionScore,
    q.AnswerCount,
    q.ViewCount,
    q.TagCount,
    q.ClosedDate,
    v.UpVotes,
    v.DownVotes,
    v.Favorites,
    rc.RecentComments,
    COALESCE(CASE 
        WHEN q.ClosedDate > TIMESTAMP '1970-01-01 00:00:00' THEN (
            SELECT cr.Name
            FROM PostHistory ph
            JOIN CloseReasonTypes cr ON CAST(ph.Comment AS INTEGER) = cr.Id
            WHERE ph.PostId = q.QuestionId AND ph.PostHistoryTypeId = 10
            ORDER BY ph.CreationDate DESC
            FETCH FIRST 1 ROW ONLY
        )
        ELSE NULL END, 'Open') AS LatestCloseReason,
    (
        SELECT COUNT(*)
        FROM AnswerCTE a 
        WHERE a.QuestionId = q.QuestionId 
          AND a.AnswerScore >= q.QuestionScore
    ) AS AnswersWithHigherOrEqualScore,
    (
        SELECT COUNT(*)
        FROM VoteAggs va2
        WHERE va2.PostId IN (SELECT a2.AnswerId FROM AnswerCTE a2 WHERE a2.QuestionId = q.QuestionId)
          AND va2.UpVotes > va2.DownVotes
    ) AS AnswersWithMoreUpvotes,
    (
        SELECT MAX(phh.CreationDate)
        FROM PostHistory phh
        WHERE phh.PostId = q.QuestionId
          AND phh.PostHistoryTypeId IN (5, 6)
    ) AS LastEditOrTagEditTime,
    LEAST(
        COALESCE(q.QuestionScore,0) + COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0) + COALESCE(v.Favorites,0),
        GREATEST(COALESCE(q.QuestionScore,0),0)
    ) AS NormalizedScoreRank,
    -- replace INITCAP(SPLIT_PART(...)) with standard SQL: capitalize first letter + '...'
    (CASE 
        WHEN q.Title IS NULL OR q.Title = '' THEN NULL
        ELSE UPPER(SUBSTR(SPLIT_PART(q.Title, ' ', 1),1,1)) || LOWER(SUBSTR(SPLIT_PART(q.Title, ' ', 1),2)) || '...'
    END) AS FirstWordOfTitle
FROM QuestionCTE q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN UserBadgeStats qb ON qb.UserId = u.Id
LEFT JOIN VoteAggs v ON v.PostId = q.QuestionId
LEFT JOIN RecentComments rc ON rc.PostId = q.QuestionId
LEFT JOIN LongestCloseReason lcr ON lcr.CloseReasonId = (
    SELECT ph.Comment
    FROM PostHistory ph
    WHERE ph.PostId = q.QuestionId AND ph.PostHistoryTypeId = 10
    ORDER BY LENGTH(ph.Comment) DESC NULLS LAST
    FETCH FIRST 1 ROW ONLY
)
WHERE (q.ViewCount > 50 OR (q.ClosedDate > TIMESTAMP '1970-01-01 00:00:00' AND q.AnswerCount > 0))
  AND COALESCE(q.TagCount,0) BETWEEN 1 AND 5
ORDER BY 
    NormalizedScoreRank DESC,
    q.ViewCount DESC NULLS LAST,
    qb.GoldBadges DESC NULLS LAST
FETCH FIRST 50 ROWS ONLY;