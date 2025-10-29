WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(t.ExcerptPostId, 0) AS ExcerptPostId,
        COALESCE(t.WikiPostId, 0) AS WikiPostId,
        0 AS Level,
        CAST(t.TagName AS varchar) AS TagPath
    FROM Tags t
    WHERE t.IsRequired = TRUE
    UNION ALL
    SELECT 
        c.Id,
        c.TagName,
        c.Count,
        COALESCE(c.ExcerptPostId, 0) AS ExcerptPostId,
        COALESCE(c.WikiPostId, 0) AS WikiPostId,
        r.Level + 1 AS Level,
        r.TagPath || ' > ' || c.TagName AS TagPath
    FROM Tags c
    JOIN RecursiveTagHierarchy r ON c.IsRequired = TRUE AND c.Id > r.Id AND c.Count < r.Count
    WHERE r.Level < 3
), UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        MAX(p.Score) AS MaxPostScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS RankByReputation
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
), PopularQuestions AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        array_to_string(array_agg(DISTINCT pht.Name ORDER BY pht.Name), ', ') AS HistoryEvents,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND (c.Text ~* 'performance|benchmark|slow|optimization')) AS RelevantComments,
        LEAD(p.Score) OVER (ORDER BY p.Score DESC, p.Id) AS NextScore,
        LAG(p.Score) OVER (ORDER BY p.Score DESC, p.Id) AS PrevScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE p.PostTypeId = 1
      AND p.Score > 10
      AND p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '3 year')
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags
)
SELECT 
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TagBasedBadges,
    ROUND(u.AvgPostScore::numeric,2) AS AvgPostScore,
    u.MaxPostScore,
    u.PostCount,
    pq.Id AS TopQuestionId,
    pq.Title AS TopQuestionTitle,
    pq.Score AS TopQuestionScore,
    pq.ViewCount AS TopQuestionViews,
    pq.AnswerCount AS TopQuestionAnswers,
    pq.HistoryEvents,
    pq.RelevantComments,
    CASE 
        WHEN pq.NextScore IS NULL THEN NULL
        ELSE 'Next higher score: ' || CAST(pq.NextScore AS text)
    END AS NextHigherScore,
    CASE
        WHEN pq.PrevScore IS NULL THEN NULL
        ELSE 'Previous lower score: ' || CAST(pq.PrevScore AS text)
    END AS PreviousLowerScore,
    rth.TagPath AS SampleTagPath,
    rth.Level AS SampleTagLevel
FROM UserStats u
LEFT JOIN LATERAL (
    SELECT p.*
    FROM PopularQuestions p
    WHERE p.OwnerUserId = u.UserId
    ORDER BY p.Score DESC, p.CreationDate DESC, p.Id
    LIMIT 1
) pq ON TRUE
LEFT JOIN RecursiveTagHierarchy rth ON POSITION(rth.TagName IN COALESCE(pq.Tags, '')) > 0
WHERE u.PostCount > 20
  AND u.Reputation > 5000
  AND (u.GoldBadges + u.SilverBadges + u.BronzeBadges) > 5
ORDER BY u.Reputation DESC, u.PostCount DESC
LIMIT 50;