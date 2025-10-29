-- {"query": "2813.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1672} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath,
        1 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
  UNION ALL
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName,
        r.Depth + 1
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy r ON substring(t.TagName, 1, length(array_to_string(r.TagPath, '') ) ) = array_to_string(r.TagPath, '')
    WHERE r.Depth < 3 AND t.Id <> r.Id
),
FilteredQuestions AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Reputation AS OwnerReputation,
        COALESCE(p.FavoriteCount,0) AS Favorites,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS OwnerTopQuestionRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- questions only
      AND p.CreationDate >= '2019-01-01' AND p.CreationDate < '2024-01-01'
      AND p.Tags IS NOT NULL
      AND p.Score >= 0
),
AnswerStats AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotes,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        COUNT(a.Id) AS TotalAnswers,
        SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswersByRegistered
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.CreationDate < NOW()
    WHERE a.PostTypeId = 2 -- answers only
    GROUP BY a.ParentId
),
BadgesPerUser AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserActivityWindow AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.Location,
        MAX(p.LastActivityDate) OVER (PARTITION BY u.Id) AS LastActivity,
        COUNT(p.Id) OVER (PARTITION BY u.Id) AS TotalPosts,
        COUNT(DISTINCT ph.PostId) OVER (PARTITION BY u.Id) AS PostsEdited
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    WHERE u.Reputation > 1000
),
ConsolidatedData AS (
    SELECT 
        fq.Id AS QuestionId,
        fq.OwnerUserId,
        fq.CreationDate AS QuestionCreation,
        fq.Score AS QuestionScore,
        fq.ViewCount,
        fq.Tags,
        fq.OwnerReputation,
        fq.Favorites,
        fq.OwnerTopQuestionRank,
        asv.TotalUpVotes,
        asv.TotalDownVotes,
        asv.AvgAnswerScore,
        asv.MaxAnswerScore,
        asv.TotalAnswers,
        asv.AnswersByRegistered,
        bpu.GoldBadges,
        bpu.SilverBadges,
        bpu.BronzeBadges,
        bpu.DistinctBadges,
        bpu.LastBadgeDate
    FROM FilteredQuestions fq
    LEFT JOIN AnswerStats asv ON fq.Id = asv.QuestionId
    LEFT JOIN BadgesPerUser bpu ON fq.OwnerUserId = bpu.UserId
    WHERE fq.OwnerTopQuestionRank = 1
),
RankedQuestions AS (
    SELECT
        cd.*,
        RANK() OVER (ORDER BY cd.Favorites DESC NULLS LAST, cd.QuestionScore DESC, cd.TotalUpVotes DESC) AS OverallRank,
        NTILE(10) OVER (ORDER BY cd.OwnerReputation DESC) AS ReputationDecile
    FROM ConsolidatedData cd
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p.Title AS PostTitle,
        rp.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts rp ON pl.RelatedPostId = rp.Id
    WHERE pl.LinkTypeId = 3 -- Duplicate links
),
CommentsPerQuestion AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName,'[anon]'), ',' ORDER BY c.UserDisplayName) AS Commenters
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    rq.QuestionId,
    rq.Tags,
    rq.QuestionCreation::date AS QuestionDate,
    rq.QuestionScore,
    rq.ViewCount,
    rq.Favorites,
    rq.TotalAnswers,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.TotalUpVotes,
    rq.TotalDownVotes,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.DistinctBadges,
    rq.LastBadgeDate,
    rq.ReputationDecile,
    dq.RelatedPostTitle AS DuplicateOf,
    cpq.CommentCount,
    cpq.AvgCommentScore,
    cpq.Commenters,
    CASE 
        WHEN rq.OwnerReputation > 100000 THEN 'Legend'
        WHEN rq.OwnerReputation BETWEEN 10000 AND 100000 THEN 'Expert'
        WHEN rq.OwnerReputation BETWEEN 1000 AND 9999 THEN 'Intermediate'
        ELSE 'Novice'
    END AS UserLevel,
    -- calculated string expression
    CONCAT(
      LEFT(rq.Tags, 20), 
      '...(', rq.TotalAnswers, ' answers; ', rq.Favorites, ' favorites)', 
      COALESCE(' [Top user badge count: ' || rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges || ']', '')
    ) AS SummaryInfo,
    -- complicated predicate with NULL logic and nested CASE
    CASE 
        WHEN rq.TotalAnswers IS NULL OR rq.TotalAnswers = 0 THEN 'No answers'
        WHEN rq.AvgAnswerScore >= 5 AND rq.MaxAnswerScore >= 10 THEN 
            CASE WHEN rq.Favorites >= 10 THEN 'High quality popular Q&A' ELSE 'High quality Q&A' END
        WHEN rq.QuestionScore < 0 THEN 'Negative scored question'
        ELSE 'Moderate or low quality'
    END AS QualityAssessment
FROM RankedQuestions rq
LEFT JOIN DuplicateLinks dq ON rq.QuestionId = dq.PostId
LEFT JOIN CommentsPerQuestion cpq ON rq.QuestionId = cpq.PostId
WHERE rq.QuestionCreation >= '2020-01-01'
  AND (
    rq.Favorites > 0 OR
    rq.TotalAnswers > 5 OR
    (rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges) > 0
  )
ORDER BY rq.OverallRank, rq.QuestionScore DESC NULLS LAST
LIMIT 100;
