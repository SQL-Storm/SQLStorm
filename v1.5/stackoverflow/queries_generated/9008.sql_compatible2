WITH recent_q AS (
    SELECT
        p.Id AS QId,
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS Author,
        COALESCE(p.ViewCount, 0) AS Views,
        COUNT(c.Id) FILTER (WHERE c.Score >= 0) AS PositiveComments,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(p.CreationDate AS DATE)
            ORDER BY p.Score DESC
        ) AS DayRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2024-10-01' - INTERVAL '60 days'
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName, p.ViewCount
),
top_q AS (
    SELECT * FROM recent_q
    WHERE DayRank <= 5
),
ans_stats AS (
    SELECT
        ParentId AS QId,
        COUNT(*) AS AnswerCount,
        AVG(Score) AS AvgAnsScore,
        MAX(Score) AS MaxAnsScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
badge_stats AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
dup_links AS (
    SELECT
        pl.PostId AS QId,
        COUNT(*) AS DupCount
    FROM PostLinks pl
    JOIN LinkTypes lt
      ON lt.Id = pl.LinkTypeId
     AND lt.Name = 'Duplicate'
    GROUP BY pl.PostId
),
combined AS (
    SELECT
        tq.QId,
        tq.Title,
        tq.CreationDate,
        tq.Score AS QScore,
        tq.Views,
        tq.PositiveComments,
        asd.AnswerCount,
        asd.AvgAnsScore,
        asd.MaxAnsScore,
        bs.Gold,
        bs.Silver,
        bs.Bronze,
        bs.LastBadgeDate,
        COALESCE(dl.DupCount, 0) AS Dups,
        CAST(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - tq.CreationDate) AS INTEGER) AS AgeDays,
        (
            SELECT Text
            FROM Comments cc
            WHERE cc.PostId = tq.QId
              AND cc.UserId IS NOT NULL
            ORDER BY cc.CreationDate DESC
            LIMIT 1
        ) AS LastComment
    FROM top_q tq
    LEFT JOIN ans_stats asd ON asd.QId = tq.QId
    LEFT JOIN Posts p ON p.Id = tq.QId
    LEFT JOIN badge_stats bs ON bs.UserId = p.OwnerUserId
    LEFT JOIN dup_links dl ON dl.QId = tq.QId
)
SELECT
    c.QId,
    c.Title,
    c.CreationDate,
    c.QScore,
    c.Views,
    c.PositiveComments,
    c.AnswerCount,
    c.AvgAnsScore,
    c.MaxAnsScore,
    c.Gold,
    c.Silver,
    c.Bronze,
    COALESCE(c.LastBadgeDate, c.CreationDate) AS EffectiveBadgeDate,
    c.Dups,
    c.AgeDays,
    CASE
        WHEN c.AnswerCount = 0 THEN 'Unanswered'
        WHEN c.AvgAnsScore > c.QScore THEN 'High Engagement'
        ELSE 'Moderate'
    END AS EngagementCategory,
    CONCAT(
        SUBSTR(c.Title, 1, 20),
        CASE WHEN LENGTH(c.Title) > 20 THEN '…' ELSE '' END
    ) AS ShortTitle,
    COALESCE(c.LastComment, '–') AS LastCommentText
FROM combined c
WHERE c.Dups = 0
  AND c.QScore > (
      SELECT PERCENTILE_CONT(0.5)
             WITHIN GROUP (ORDER BY Score)
        FROM Posts
       WHERE PostTypeId = 1
  )
UNION ALL
SELECT
    c.QId,
    c.Title,
    c.CreationDate,
    c.QScore,
    c.Views,
    c.PositiveComments,
    c.AnswerCount,
    c.AvgAnsScore,
    c.MaxAnsScore,
    c.Gold,
    c.Silver,
    c.Bronze,
    TIMESTAMP '2024-10-01 12:34:56' AS EffectiveBadgeDate,
    c.Dups,
    c.AgeDays,
    'Fallback' AS EngagementCategory,
    'N/A' AS ShortTitle,
    'N/A' AS LastCommentText
FROM combined c
ORDER BY EngagementCategory, QScore DESC
LIMIT 50;