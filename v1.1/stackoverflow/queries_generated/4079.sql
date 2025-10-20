-- {"query": "4079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1750} 

WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, 1 as Level,
           COALESCE(EXTRACT(EPOCH FROM (NOW() - p.CreationDate))/86400, NULL) AS AgeDays,
           p.ViewCount, p.Score,
           ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInTag
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.TagName IS NOT NULL

    UNION ALL

    SELECT th.Id, th.TagName, rh.Level + 1,
           rh.AgeDays, rh.ViewCount, rh.Score,
           rh.RankInTag
    FROM RecursiveTagHierarchy rh
    INNER JOIN Tags th ON th.WikiPostId = (SELECT p.Id FROM Posts p WHERE p.Tags ILIKE '%' || rh.TagName || '%' LIMIT 1)
    WHERE rh.Level < 3
),
UserBadgeCounts AS (
    SELECT 
        b.UserId, 
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostOwnerStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(ubc.GoldBadges,0) AS GoldBadges,
        COALESCE(ubc.SilverBadges,0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ubc.TotalBadges,0) AS TotalBadges,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS MaxPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.TotalBadges
),
RecentClosedQuestions AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes crt ON crt.Id::int = CAST(ph.Comment AS int) 
        AND ph.PostHistoryTypeId = 10
    INNER JOIN Posts p ON p.Id = ph.PostId AND p.PostTypeId = 1
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE ph.CreationDate > NOW() - INTERVAL '6 months'
),
AnswerWithAcceptedRank AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        q.AcceptedAnswerId
    FROM Posts a
    INNER JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
FinalSelection AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        COALESCE(ac.QuestionCloseCount,0) AS RecentClosureCount,
        aw.AnswerRank,
        CASE WHEN p.Id = q.AcceptedAnswerId THEN true ELSE false END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerPostRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS QuestionCloseCount FROM RecentClosedQuestions GROUP BY PostId
    ) ac ON ac.PostId = p.Id
    LEFT JOIN AnswerWithAcceptedRank aw ON aw.AnswerId = p.Id
    LEFT JOIN Posts q ON q.Id = aw.QuestionId
    WHERE p.Score IS NOT NULL
)
SELECT 
    fs.PostId,
    fs.PostTypeId,
    fs.Title,
    fs.Score,
    fs.ViewCount,
    fs.Tags,
    fs.OwnerName,
    fs.OwnerReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.RecentClosureCount,
    fs.AnswerRank,
    fs.IsAcceptedAnswer,
    lhs.Level AS TagHierarchyLevel,
    lhs.AgeDays AS TagExcerptAgeInDays,
    COALESCE(usr.QuestionCount,0) AS OwnerQuestionCount,
    COALESCE(usr.AnswerCount,0) AS OwnerAnswerCount,
    COALESCE(usr.AvgPostScore,0) AS OwnerAveragePostScore,
    COALESCE(usr.MaxPostScore,0) AS OwnerMaxPostScore,
    CASE 
        WHEN fs.Score > 10 AND fs.ViewCount > 1000 THEN 'HighImpact'
        WHEN fs.Score <= 10 AND fs.ViewCount > 1000 THEN 'PopularLowScore'
        WHEN fs.Score > 10 AND fs.ViewCount <= 1000 THEN 'HighScoreLowView'
        ELSE 'Regular'
    END AS PostImpactCategory,
    CONCAT_WS(' | ', LEFT(fs.Title, 50), LEFT(fs.Tags, 30)) AS TitleAndTagsSnippet,
    LENGTH(fs.Tags) - LENGTH(REPLACE(fs.Tags, '><', '')) + 1 AS TagCountEstimate
FROM FinalSelection fs
LEFT JOIN RecursiveTagHierarchy lhs ON lhs.TagName = (SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM COALESCE(fs.Tags, '')), '><')) LIMIT 1)
LEFT JOIN PostOwnerStats usr ON usr.UserId = fs.OwnerUserId
WHERE (fs.PostTypeId = 1 OR (fs.PostTypeId = 2 AND fs.AnswerRank <= 3))
  AND (fs.Score > 5 OR fs.ViewCount > 500)
UNION
SELECT 
    c.Id AS PostId,
    0 AS PostTypeId,
    CONCAT('Comment on Post ', c.PostId) AS Title,
    c.Score,
    NULL AS ViewCount,
    NULL AS Tags,
    c.UserDisplayName AS OwnerName,
    NULL AS OwnerReputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS RecentClosureCount,
    NULL AS AnswerRank,
    NULL AS IsAcceptedAnswer,
    NULL AS TagHierarchyLevel,
    NULL AS TagExcerptAgeInDays,
    0 AS OwnerQuestionCount,
    0 AS OwnerAnswerCount,
    0 AS OwnerAveragePostScore,
    0 AS OwnerMaxPostScore,
    'Comment' AS PostImpactCategory,
    LEFT(c.Text, 80) AS TitleAndTagsSnippet,
    0 AS TagCountEstimate
FROM Comments c
WHERE EXISTS (
    SELECT 1 FROM Posts p WHERE p.Id = c.PostId AND p.Score > 20
)
ORDER BY Score DESC, ViewCount DESC NULLS LAST
LIMIT 100;
