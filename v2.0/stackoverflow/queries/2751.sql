-- {"query": "2751.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1663}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        tags_parent.TagName AS ParentTagName,
        1 AS Level
    FROM Tags t
    LEFT JOIN PostLinks pl ON pl.PostId = t.ExcerptPostId AND pl.LinkTypeId = 1
    LEFT JOIN Posts p ON p.Id = pl.RelatedPostId AND p.PostTypeId = 1
    LEFT JOIN (
        SELECT unnest(string_to_array(substring(p2.Tags FROM 2 FOR char_length(p2.Tags) - 2), '><')) AS TagName, p2.Id AS p_id
        FROM Posts p2
    ) tags_parent ON tags_parent.p_id = p.Id
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        rh.ParentTagName,
        rh.Level + 1
    FROM Tags c
    JOIN RecursiveTagHierarchy rh ON rh.ParentTagName = c.TagName
    WHERE rh.Level < 3
),
TopActiveUsers AS (
    SELECT 
        u.Id, u.DisplayName, u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT ans.Id) AS AnswerCount,
        COALESCE(SUM(vt_upcnt.UpVotes), 0) AS TotalUpVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts ans ON ans.OwnerUserId = u.Id AND ans.PostTypeId = 2
    LEFT JOIN (
        SELECT 
            ps.OwnerUserId, SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes
        FROM Posts ps
        JOIN Votes v ON v.PostId = ps.Id
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE ps.OwnerUserId IS NOT NULL
        GROUP BY ps.OwnerUserId
    ) vt_upcnt ON vt_upcnt.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, vt_upcnt.UpVotes
    HAVING COUNT(DISTINCT p.Id) > 5 AND COUNT(DISTINCT ans.Id) > 5
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.Tags ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.Tags ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate IS NOT NULL
),
CloseReasonCounts AS (
    SELECT
        chr.Name AS CloseReason,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    JOIN CloseReasonTypes chr ON chr.Id = CAST(ph.Comment AS SMALLINT) AND ph.PostHistoryTypeId = 10
    WHERE ph.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY chr.Name
    HAVING COUNT(ph.Id) > 10
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount,
        COUNT(DISTINCT b.TagBased) AS BadgeTagVariety
    FROM Badges b
    GROUP BY b.UserId
),
AggregatedPostStats AS (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.FavoriteCount) AS TotalFavorites,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        MAX(p.LastActivityDate) AS LastActivity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
HighImpactPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerName,
        COALESCE(ab.GoldBadgeCount, 0) AS OwnerGoldBadges,
        COALESCE(ab.SilverBadgeCount, 0) AS OwnerSilverBadges,
        COALESCE(ab.BronzeBadgeCount, 0) AS OwnerBronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM Posts p
    JOIN PostTypes pt ON pt.Id = p.PostTypeId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeStats ab ON ab.UserId = p.OwnerUserId
    WHERE p.Score > 10 AND p.ViewCount > 1000 AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
),
FinalStats AS (
    SELECT
        tu.Id AS UserId,
        tu.DisplayName,
        tu.Reputation,
        ag.QuestionsAsked,
        ag.AnswersGiven,
        ag.AvgScore,
        ag.TotalViews,
        ag.TotalFavorites,
        cr.CloseReason,
        cr.CloseCount,
        COALESCE(tg_tags.Level, 0) AS TagHierarchyLevel,
        hi.PostRank,
        hi.Title AS TopPostTitle,
        hi.Score AS TopPostScore,
        hi.ViewCount AS TopPostViews,
        hi.PostTypeName,
        tu.rn
    FROM TopActiveUsers tu
    LEFT JOIN AggregatedPostStats ag ON ag.OwnerUserId = tu.Id
    LEFT JOIN CloseReasonCounts cr ON cr.CloseReason IS NOT NULL
    LEFT JOIN RecursiveTagHierarchy tg_tags ON tg_tags.TagName = (
        SELECT unnest(string_to_array(substring(p2.Tags FROM 2 FOR char_length(p2.Tags) - 2), '><')) FROM Posts p2 WHERE p2.OwnerUserId = tu.Id LIMIT 1
    )
    LEFT JOIN HighImpactPosts hi ON hi.OwnerName = tu.DisplayName
    WHERE tu.rn <= 20
)
SELECT
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.QuestionsAsked,
    fs.AnswersGiven,
    ROUND(CAST(fs.AvgScore AS numeric), 2) AS AvgScore,
    fs.TotalViews,
    fs.TotalFavorites,
    fs.CloseReason,
    fs.CloseCount,
    fs.TagHierarchyLevel,
    fs.PostRank,
    SUBSTRING(fs.TopPostTitle FROM 1 FOR 60) AS TopPostTitleSnippet,
    fs.TopPostScore,
    fs.TopPostViews,
    fs.PostTypeName,
    CASE
        WHEN fs.TotalViews > 10000 AND fs.AvgScore > 5 THEN 'High Impact User'
        WHEN fs.TotalViews BETWEEN 5000 AND 10000 THEN 'Moderate Impact User'
        ELSE 'Low Impact User'
    END AS ImpactCategory
FROM FinalStats fs
WHERE fs.CloseCount IS NULL OR fs.CloseCount < 100
ORDER BY fs.Reputation DESC, fs.TopPostScore DESC, fs.TotalViews DESC;