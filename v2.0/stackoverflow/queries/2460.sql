-- {"query": "2460.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1543}
WITH RECURSIVE RecursivePosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Id AS OwnerUserId,
        u.Reputation,
        u.DisplayName,
        row_number() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.Tags IS NOT NULL

    UNION ALL

    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Id,
        u.Reputation,
        u.DisplayName,
        1
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    INNER JOIN RecursivePosts rp ON p.ParentId = rp.Id
    WHERE p.PostTypeId = 2 AND rp.rn = 1
),
TaggedQuestions AS (
    SELECT 
        Id,
        Tags,
        regexp_split_to_table(substring(Tags FROM 2 FOR length(Tags) - 2), '><') AS Tag
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
),
TopTags AS (
    SELECT 
        Tag,
        count(*) AS QuestionCount
    FROM TaggedQuestions
    GROUP BY Tag
    ORDER BY QuestionCount DESC
    LIMIT 10
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        b.Class,
        count(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        coalesce(max(case when Class = 1 then BadgeCount end), 0) AS GoldBadges,
        coalesce(max(case when Class = 2 then BadgeCount end), 0) AS SilverBadges,
        coalesce(max(case when Class = 3 then BadgeCount end), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
    GROUP BY u.Id
),
PostScoresWindow AS (
    SELECT 
        Id AS PostId,
        Score,
        sum(case when Score > 0 then Score else 0 end) OVER (PARTITION BY Id ORDER BY Id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativePositiveScore,
        avg(Score) OVER (PARTITION BY Id) AS AvgScore,
        count(*) OVER () AS TotalPosts
    FROM Posts
),
PostAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreated,
        count(a.Id) AS AnswerCount,
        coalesce(avg(a.Score),0) AS AvgAnswerScore,
        max(a.Score) AS HighestAnswerScore,
        sum(case when a.Score > 5 then 1 else 0 end) AS HighScoreAnswerCount
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate
),
PostCloseReasons AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo AS (
    SELECT 
        q.Id,
        q.Title,
        pcr.CloseReason,
        pcr.CloseDate
    FROM Posts q
    LEFT JOIN PostCloseReasons pcr ON q.Id = pcr.PostId
    WHERE q.PostTypeId = 1
),
DuplicateLinks AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId,
        p1.Title AS OriginalTitle,
        p2.Title AS DuplicateTitle
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id AND lt.Name = 'Duplicate'
    INNER JOIN Posts p1 ON pl.PostId = p1.Id
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
)
SELECT 
    tp.Tag AS TopTag,
    ps.QuestionId,
    ps.Title AS QuestionTitle,
    ps.QuestionCreated,
    ps.AnswerCount,
    ps.AvgAnswerScore,
    ps.HighestAnswerScore,
    ps.HighScoreAnswerCount,
    u.DisplayName AS QuestionOwner,
    u.Reputation AS QuestionOwnerReputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    coalesce(qc.CloseReason, 'Open') AS CloseStatus,
    qc.CloseDate,
    dl.DuplicateTitle,
    array_agg(DISTINCT pht.Name) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS RecentEditTypes,
    concat_ws(' | ', 
              'Score:', coalesce(CAST(p.Score AS text), '0'),
              'Views:', coalesce(CAST(p.ViewCount AS text), '0'),
              'Favorites:', coalesce(CAST(p.FavoriteCount AS text), '0')) AS StatsSummary,
    CASE 
        WHEN p.LastActivityDate IS NULL THEN 'No recent activity'
        WHEN p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days' THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus,
    ph.PostHistoryTypeId AS ph_PostHistoryTypeId,
    pht.Name AS ph_PostHistoryName
FROM TopTags tp
INNER JOIN TaggedQuestions tq ON tq.Tag = tp.Tag
INNER JOIN PostAnswerStats ps ON ps.QuestionId = tq.Id
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = ps.QuestionId LIMIT 1)
LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = u.Id
LEFT JOIN QuestionsWithCloseInfo qc ON qc.Id = ps.QuestionId
LEFT JOIN Posts p ON p.Id = ps.QuestionId
LEFT JOIN DuplicateLinks dl ON dl.PostId = ps.QuestionId
LEFT JOIN LATERAL (
    SELECT ph2.PostHistoryTypeId, pht2.Name, ph2.CreationDate
    FROM PostHistory ph2
    INNER JOIN PostHistoryTypes pht2 ON ph2.PostHistoryTypeId = pht2.Id
    WHERE ph2.PostId = ps.QuestionId
    ORDER BY ph2.CreationDate DESC
    LIMIT 5
) ph ON TRUE
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE ps.AnswerCount > 3
  AND (u.Reputation > 1000 OR u.Reputation IS NULL)
GROUP BY
    tp.Tag,
    ps.QuestionId,
    ps.Title,
    ps.QuestionCreated,
    ps.AnswerCount,
    ps.AvgAnswerScore,
    ps.HighestAnswerScore,
    ps.HighScoreAnswerCount,
    u.DisplayName,
    u.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    qc.CloseReason,
    qc.CloseDate,
    dl.DuplicateTitle,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.LastActivityDate,
    ph.PostHistoryTypeId,
    pht.Name
ORDER BY ps.HighScoreAnswerCount DESC, ps.AnswerCount DESC, ps.AvgAnswerScore DESC
LIMIT 100;