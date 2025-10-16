-- {"query": "693.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2005} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS AncestorTags
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
  UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.AncestorTags || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id > r.Id
    WHERE t.IsModeratorOnly = 0 AND NOT t.TagName = ANY(r.AncestorTags)
    AND r.Level < 3
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostScoreRanks AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserRecentPostRank
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
AnswerAcceptanceRate AS (
    SELECT
        u.Id AS UserId,
        COUNT(a.Id) AS TotalAnswers,
        COUNT(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 END) AS AcceptedAnswers,
        CASE WHEN COUNT(a.Id) = 0 THEN NULL ELSE ROUND(COUNT(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 END)::NUMERIC / COUNT(a.Id), 4) END AS AcceptanceRate
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    GROUP BY u.Id
),
PostCommentsSummary AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT COALESCE(NULLIF(TRIM(c.UserDisplayName), ''), 'Anonymous'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
),
QuestionsWithComplexFilters AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        us.AcceptanceRate,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        pc.CommentCount,
        pc.AvgCommentScore,
        pc.LastCommentDate,
        pc.Commenters,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank,
        LENGTH(p.Body) AS BodyLength,
        CASE WHEN p.ClosedDate IS NULL THEN 0 ELSE 1 END AS IsClosed,
        EXISTS (
            SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) AS HasDuplicateLinks
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN AnswerAcceptanceRate us ON us.UserId = p.OwnerUserId
    LEFT JOIN UserBadgeStats ub ON ub.UserId = p.OwnerUserId
    LEFT JOIN PostCommentsSummary pc ON pc.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '2 years'
      AND p.Score > 0
),
DuplicateQuestions AS (
    SELECT DISTINCT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
ComplexUserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(us.AcceptanceRate, 0) AS AcceptanceRate,
        COALESCE(ub.TotalBadges, 0) AS TotalBadges,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS MaxPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN AnswerAcceptanceRate us ON us.UserId = u.Id
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, us.AcceptanceRate, ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
FinalResult AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerName,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.AcceptanceRate,
        q.TotalBadges,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.CommentCount,
        q.AvgCommentScore,
        q.LastCommentDate,
        q.Commenters,
        dq.OriginalPostId AS DuplicateOf,
        cu.Reputation AS OwnerReputation,
        cu.QuestionCount AS OwnerQuestionCount,
        cu.AnswerCount AS OwnerAnswerCount,
        cu.TotalPostScore AS OwnerTotalPostScore,
        cu.TotalComments AS OwnerTotalComments,
        CASE 
            WHEN q.IsClosed = 1 THEN 'Closed' 
            ELSE 'Open' 
        END AS PostStatus,
        q.BodyLength,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) AS OwnerPostRank
    FROM QuestionsWithComplexFilters q
    LEFT JOIN DuplicateQuestions dq ON dq.DuplicatePostId = q.Id
    LEFT JOIN ComplexUserStats cu ON cu.Id = q.OwnerUserId
    WHERE q.HasDuplicateLinks = TRUE OR q.FavoriteCount > 10 OR q.CommentCount > 5
)
SELECT
    fr.*,
    STRING_AGG(DISTINCT rt.TagName, ' > ' ORDER BY rt.Level) AS TagHierarchy,
    CONCAT(
        SUBSTRING(fr.Title FROM 1 FOR 50),
        CASE WHEN LENGTH(fr.Title) > 50 THEN '...' ELSE '' END
    ) AS ShortTitle,
    CASE
        WHEN fr.Score > 100 THEN 'Hot'
        WHEN fr.Score BETWEEN 50 AND 100 THEN 'Popular'
        ELSE 'Normal'
    END AS PopularityLabel
FROM FinalResult fr
LEFT JOIN Posts p ON p.Id = fr.QuestionId
LEFT JOIN LATERAL (
    SELECT rt.*
    FROM RecursiveTagHierarchy rt
    WHERE rt.TagName = ANY(string_to_array(substring(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))
    ORDER BY rt.Level DESC
    LIMIT 3
) rt ON TRUE
GROUP BY
    fr.QuestionId,
    fr.Title,
    fr.OwnerUserId,
    fr.OwnerName,
    fr.CreationDate,
    fr.Score,
    fr.ViewCount,
    fr.AnswerCount,
    fr.FavoriteCount,
    fr.AcceptanceRate,
    fr.TotalBadges,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.CommentCount,
    fr.AvgCommentScore,
    fr.LastCommentDate,
    fr.Commenters,
    fr.DuplicateOf,
    fr.OwnerReputation,
    fr.OwnerQuestionCount,
    fr.OwnerAnswerCount,
    fr.OwnerTotalPostScore,
    fr.OwnerTotalComments,
    fr.PostStatus,
    fr.BodyLength,
    fr.OwnerPostRank
ORDER BY fr.Score DESC, fr.ViewCount DESC, fr.CreationDate DESC
LIMIT 100;
