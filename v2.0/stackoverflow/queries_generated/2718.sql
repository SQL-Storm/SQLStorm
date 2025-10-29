-- {"query": "2718.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1479} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        ARRAY[t.TagName] AS Path
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1 AS Level,
        r.Path || t.TagName
    FROM Tags t
    JOIN PostLinks pl ON pl.PostId = t.ExcerptPostId
    JOIN RecursiveTagHierarchy r ON pl.RelatedPostId = r.Id
    WHERE t.TagName IS NOT NULL AND NOT t.TagName = ANY(r.Path)
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(MAX(b.Date), '1970-01-01') AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostAggregates AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Title, '') AS Title,
        COALESCE(p.Tags, '') AS Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankWithinType,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        EXISTS (
            SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5
        ) AS HasHighScoreComment,
        (SELECT AVG(s.Score) FROM Posts s WHERE s.ParentId = p.Id) AS AvgAnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotesCount
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
),
CorrelatedAnswerStats AS (
    SELECT
        p.ParentId,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        COUNT(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
FilteredQuestions AS (
    SELECT
        pa.*,
        cas.AvgAnswerScore,
        cas.MaxAnswerScore,
        cas.AnswerCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
    FROM PostAggregates pa
    LEFT JOIN CorrelatedAnswerStats cas ON cas.ParentId = pa.PostId
    LEFT JOIN UserBadgeStats ub ON ub.UserId = pa.OwnerUserId
    WHERE pa.PostTypeId = 1 
      AND pa.Score > 0 
      AND pa.IsClosed = 0
      AND pa.AnswerCount > 0
      AND ub.GoldBadges + ub.SilverBadges + ub.BronzeBadges > 0
),
FinalSelection AS (
    SELECT 
        fq.PostId,
        fq.Title,
        fq.OwnerName,
        fq.Score,
        fq.ViewCount,
        fq.AnswerCount,
        fq.AvgAnswerScore,
        fq.MaxAnswerScore,
        fq.GoldBadges,
        fq.SilverBadges,
        fq.BronzeBadges,
        fq.Tags,
        -- Extract first three tags as array
        string_to_array(substring(fq.Tags from 2 for length(fq.Tags)-2), '><') AS TagArray
    FROM FilteredQuestions fq
),
ExplodedTags AS (
    SELECT
        fs.PostId,
        tag,
        ROW_NUMBER() OVER (PARTITION BY fs.PostId ORDER BY tag) as TagOrder
    FROM FinalSelection fs,
         unnest(fs.TagArray) AS tag
)
SELECT
    fs.PostId,
    fs.Title,
    fs.OwnerName,
    fs.Score,
    fs.ViewCount,
    fs.AnswerCount,
    fs.AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    STRING_AGG(DISTINCT et.tag, ', ') FILTER (WHERE et.TagOrder <= 3) AS Top3Tags,
    -- Complex string expression combining title length and tag count
    LENGTH(fs.Title) * CARDINALITY(fs.TagArray) AS TitleTagWeight,
    -- Complex predicate: high scoring posts with more silver badges than gold and sum of badge counts above threshold
    CASE 
        WHEN fs.Score > 10 AND fs.SilverBadges > fs.GoldBadges AND (fs.GoldBadges + fs.SilverBadges + fs.BronzeBadges) >= 5 THEN 'HighReputationExpert'
        ELSE 'RegularUser'
    END AS UserCategory
FROM FinalSelection fs
LEFT JOIN ExplodedTags et ON et.PostId = fs.PostId
GROUP BY fs.PostId, fs.Title, fs.OwnerName, fs.Score, fs.ViewCount, fs.AnswerCount, fs.AvgAnswerScore, fs.MaxAnswerScore, fs.GoldBadges, fs.SilverBadges, fs.BronzeBadges, fs.TagArray
ORDER BY fs.Score DESC NULLS LAST, fs.ViewCount DESC NULLS LAST
LIMIT 25
UNION
SELECT
    p.Id AS PostId,
    COALESCE(p.Title, '') AS Title,
    COALESCE(u.DisplayName, 'unknown') AS OwnerName,
    p.Score,
    p.ViewCount,
    0 AS AnswerCount,
    NULL::float AS AvgAnswerScore,
    NULL::int AS MaxAnswerScore,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    '' AS Top3Tags,
    0 AS TitleTagWeight,
    'OrphanPost' AS UserCategory
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1 
  AND p.Score <= 0
ORDER BY p.CreationDate DESC
LIMIT 5;
