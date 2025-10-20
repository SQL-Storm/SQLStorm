-- {"query": "21027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1986} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT p.Id) AS PostCount,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.CreationDate < CURRENT_DATE
    WHERE u.Reputation >= 100
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 0
),
UserAchievements AS (
    SELECT au.Id,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBadges,
           STRING_AGG(DISTINCT b.Name, '; ') AS BadgeNames
    FROM ActiveUsers au
    LEFT JOIN Badges b ON au.Id = b.UserId 
        AND b.Date >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY au.Id
),
QuestionPerformance AS (
    SELECT p.Id AS QuestionId,
           p.Title,
           p.Score AS QuestionScore,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.CreationDate,
           p.ClosedDate IS NOT NULL AS IsClosed,
           COALESCE(p.ClosedDate, p.CreationDate) AS ActivityEndDate,
           ROW_NUMBER() OVER (PARTITION BY EXTRACT(MONTH FROM p.CreationDate), EXTRACT(YEAR FROM p.CreationDate) 
                              ORDER BY p.ViewCount DESC NULLS LAST) AS MonthlyViewRank,
           AVG(p.Score) OVER (PARTITION BY EXTRACT(MONTH FROM p.CreationDate), EXTRACT(YEAR FROM p.CreationDate)) AS MonthlyAvgScore,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevQuestionScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.DeletionDate IS NULL
),
AnswerQuality AS (
    SELECT a.Id AS AnswerId,
           a.ParentId AS QuestionId,
           a.Score AS AnswerScore,
           a.CreationDate AS AnswerDate,
           CASE 
               WHEN a.Score >= 5 THEN 'High Quality'
               WHEN a.Score BETWEEN 0 AND 4 THEN 'Average'
               ELSE 'Low Quality'
           END AS QualityTier,
           NTILE(4) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS AnswerRankInQuestion,
           FIRST_VALUE(a.Score) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate 
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS BestAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2 
        AND a.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
LinkNetwork AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           lt.Name AS LinkType,
           p.Score AS SourceScore,
           rp.Score AS TargetScore,
           CASE 
               WHEN pl.LinkTypeId = 1 THEN 'Reference Link'
               WHEN pl.LinkTypeId = 3 THEN 'Duplicate Link'
               ELSE 'Other'
           END AS LinkCategory
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    INNER JOIN Posts p ON pl.PostId = p.Id
    INNER JOIN Posts rp ON pl.RelatedPostId = rp.Id
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.PostTypeId = 1
        AND rp.PostTypeId = 1
),
VotePatterns AS (
    SELECT v.PostId,
           vt.Name AS VoteType,
           COUNT(*) AS VoteCount,
           SUM(CASE WHEN v.VoteTypeId IN (2, 8) THEN v.BountyAmount ELSE 0 END) AS UpvoteValue,
           AVG(EXTRACT(EPOCH FROM AGE(v.CreationDate))) / 3600 AS AvgHoursToVote,
           CASE 
               WHEN COUNT(*) > (SELECT AVG(vc) FROM (SELECT COUNT(*) vc FROM Votes GROUP BY PostId) t) THEN 'High Activity'
               ELSE 'Normal Activity'
           END AS VoteActivityLevel
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND v.PostId IN (SELECT Id FROM Posts WHERE PostTypeId IN (1, 2))
    GROUP BY v.PostId, vt.Name
),
ComplexInteractions AS (
    SELECT qp.QuestionId,
           au.DisplayName AS OwnerName,
           qp.Title,
           qp.ViewCount,
           qp.AnswerCount,
           COALESCE(aq.AnswerCount, 0) AS HighQualityAnswers,
           COALESCE(ln.LinkCount, 0) AS ExternalLinks,
           COALESCE(vp.UpvoteValue, 0) AS TotalUpvotes,
           COALESCE(ua.GoldBadges, 0) AS OwnerGold,
           CASE 
               WHEN qp.IsClosed THEN 
                   CASE WHEN qp.ClosedDate - qp.CreationDate < INTERVAL '24 hours' THEN 'Quick Close'
                        ELSE 'Delayed Close' END
               ELSE 'Open'
           END AS CloseStatus,
           (qp.ViewCount * 0.1 + qp.AnswerCount * 5 + COALESCE(aq.HighQualityAnswers, 0) * 10) AS EngagementScore,
           SUBSTRING(qp.Title FROM 1 FOR 50) || 
           CASE WHEN LENGTH(qp.Tags) > 0 THEN ' [' || SUBSTRING(qp.Tags FROM 2 FOR 20) || '...]' ELSE '' END AS TitlePreview,
           CASE 
               WHEN au.PostCount IS NULL THEN NULL
               WHEN au.QuestionCount::float / NULLIF(au.PostCount, 0) > 0.7 THEN 'Question Focused'
               WHEN au.AnswerCount::float / NULLIF(au.PostCount, 0) > 0.7 THEN 'Answer Focused'
               ELSE 'Balanced'
           END AS UserFocus,
           GREATEST(qp.MonthlyViewRank, 1)::varchar || ' of ' || 
           COUNT(*) OVER (PARTITION BY EXTRACT(MONTH FROM qp.CreationDate), EXTRACT(YEAR FROM qp.CreationDate)) AS ViewRanking
    FROM QuestionPerformance qp
    LEFT JOIN ActiveUsers au ON qp.OwnerUserId = au.Id
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount, 
               SUM(CASE WHEN QualityTier = 'High Quality' THEN 1 ELSE 0 END) AS HighQualityAnswers
        FROM AnswerQuality 
        GROUP BY ParentId
    ) aq ON qp.QuestionId = aq.ParentId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS LinkCount
        FROM LinkNetwork 
        WHERE LinkCategory = 'Reference Link'
        GROUP BY PostId
    ) ln ON qp.QuestionId = ln.PostId
    LEFT JOIN UserAchievements ua ON au.Id = ua.Id
    LEFT JOIN (
        SELECT PostId, SUM(UpvoteValue) AS UpvoteValue
        FROM VotePatterns 
        WHERE VoteType LIKE '%Up%'
        GROUP BY PostId
    ) vp ON qp.QuestionId = vp.PostId
    WHERE qp.QuestionScore > (
        SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Score) 
        FROM Posts WHERE PostTypeId = 1 AND CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    )
)
SELECT ci.*,
       CASE 
           WHEN ci.EngagementScore > 100 THEN 'High Impact'
           WHEN ci.EngagementScore > 50 THEN 'Medium Impact'
           ELSE 'Low Impact'
       END AS ImpactLevel,
       (ci.TotalUpvotes * 1.0 / NULLIF(ci.ViewCount, 0)) * 100 AS UpvotePerViewRatio,
       JSON_BUILD_OBJECT(
           'owner_badges', ci.OwnerGold,
           'question_stats', JSON_BUILD_OBJECT(
               'views', ci.ViewCount,
               'answers', ci.AnswerCount,
               'score', COALESCE(ci.QuestionScore, 0)
           ),
           'external_connections', ci.ExternalLinks
       ) AS SummaryMetrics
FROM ComplexInteractions ci
WHERE ci.QuestionId NOT IN (
    SELECT DISTINCT ph.PostId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 12  -- Deleted posts
        AND ph.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
)
  AND (ci.OwnerGold > 0 OR ci.HighQualityAnswers > 2)
  AND ci.CreationDate >= CURRENT_DATE - INTERVAL '3 months'
ORDER BY ci.EngagementScore DESC NULLS LAST,
         ci.ViewCount DESC,
         COALESCE(ci.OwnerName, 'Anonymous') ASC
LIMIT 100;
