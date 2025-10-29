-- {"query": "2753.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1915} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        ARRAY[t.TagName] AS AncestorTags
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.AncestorTags || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> r.Id AND t.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeRanks AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '1 year' AND b.TagBased = 0
    GROUP BY b.UserId, b.Class
),
TopActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        COALESCE(ub.GoldCount, 0) AS GoldBadges,
        COALESCE(ub.SilverCount, 0) AS SilverBadges,
        COALESCE(ub.BronzeCount, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS Rank
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            MAX(CASE Class WHEN 1 THEN BadgeCount ELSE 0 END) AS GoldCount,
            MAX(CASE Class WHEN 2 THEN BadgeCount ELSE 0 END) AS SilverCount,
            MAX(CASE Class WHEN 3 THEN BadgeCount ELSE 0 END) AS BronzeCount
        FROM UserBadgeRanks
        GROUP BY UserId
    ) ub ON u.Id = ub.UserId
    WHERE u.Reputation > 1000
),
PostStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.Title, '') AS Title,
        CASE
            WHEN p.PostTypeId = 1 THEN ARRAY_TO_STRING(string_to_array(trim(BOTH '<>' FROM p.Tags), '><'), ', ')
            ELSE NULL
        END AS ParsedTags,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '2 years'
),
AnsweredQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwner,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS AcceptedAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.UserId = q.OwnerUserId) AS OwnerBadges,
        STRING_AGG(DISTINCT c.Name, ', ') FILTER (WHERE c.UserId IS NOT NULL) AS AllBadges,
        q.ParsedTags,
        q.Title,
        q.Score,
        q.ViewCount
    FROM PostStats q
    LEFT JOIN PostStats a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
    LEFT JOIN Badges c ON c.UserId IN (
        SELECT OwnerUserId FROM Posts p2 WHERE p2.Id = q.Id OR p2.ParentId = q.Id
    )
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.ParsedTags, q.Title, q.Score, q.ViewCount
),
FilteredDuplicates AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        p1.Score AS PostScore,
        p2.Score AS RelatedPostScore,
        CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END AS IsDuplicateLink,
        pl.CreationDate
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId IN (1,3)
),
RankedDuplicates AS (
    SELECT
        fd.*,
        ROW_NUMBER() OVER (PARTITION BY fd.PostId ORDER BY fd.RelatedPostScore DESC) AS DuplicateRank
    FROM FilteredDuplicates fd
    WHERE fd.IsDuplicateLink = 1
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
VoteAggregates AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOriginatorVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBounty
    FROM Votes v
    GROUP BY v.PostId
),
CombinedStats AS (
    SELECT
        aq.QuestionId,
        aq.Title,
        aq.ParsedTags,
        aq.Score AS QuestionScore,
        aq.ViewCount,
        aq.AnswerCount,
        aq.AcceptedAnswerScore,
        aq.AvgAnswerScore,
        COALESCE(cs.CommentCount,0) AS CommentCount,
        COALESCE(cs.AvgCommentScore,0) AS AvgCommentScore,
        COALESCE(cs.UniqueCommenters,0) AS UniqueCommenters,
        COALESCE(cs.LastCommentDate, aq.CreationDate) AS LastCommentDate,
        COALESCE(va.UpVotes,0) AS UpVotes,
        COALESCE(va.DownVotes,0) AS DownVotes,
        COALESCE(va.TotalBounty,0) AS TotalBounty,
        ta.GoldBadges,
        ta.SilverBadges,
        ta.BronzeBadges
    FROM AnsweredQuestions aq
    LEFT JOIN CommentStats cs ON cs.PostId = aq.QuestionId
    LEFT JOIN VoteAggregates va ON va.PostId = aq.QuestionId
    LEFT JOIN TopActiveUsers ta ON aq.QuestionOwner = ta.Id
    WHERE aq.AnswerCount > 0
),
FinalRanking AS (
    SELECT
        cs.*,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(NULLIF(cs.ParsedTags, ''), 'NoTag')
            ORDER BY
                cs.QuestionScore DESC,
                cs.UpVotes DESC,
                cs.ViewCount DESC,
                cs.AnswerCount DESC,
                cs.CommentCount DESC,
                cs.TotalBounty DESC
        ) AS TagRank
    FROM CombinedStats cs
    WHERE cs.CommentCount >= 3 AND cs.UpVotes > cs.DownVotes
),
FilteredRanking AS (
    SELECT *
    FROM FinalRanking
    WHERE TagRank <= 5
)
SELECT 
    fr.QuestionId,
    fr.Title,
    fr.ParsedTags,
    fr.QuestionScore,
    fr.ViewCount,
    fr.AnswerCount,
    fr.AcceptedAnswerScore,
    fr.AvgAnswerScore,
    fr.CommentCount,
    fr.AvgCommentScore,
    fr.UniqueCommenters,
    fr.LastCommentDate,
    fr.UpVotes,
    fr.DownVotes,
    fr.TotalBounty,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    CASE 
        WHEN fr.AcceptedAnswerScore IS NULL THEN 'No Accepted Answer'
        WHEN fr.AcceptedAnswerScore > fr.AvgAnswerScore THEN 'Accepted Answer Above Avg'
        ELSE 'Accepted Answer Below Avg'
    END AS AcceptedAnswerQuality,
    CASE 
        WHEN fr.TotalBounty > 0 THEN 'Bountied'
        ELSE 'No Bounty'
    END AS BountyStatus,
    CONCAT(
        'Tags: ', COALESCE(fr.ParsedTags, 'None'), '; ',
        'Badges: G:', fr.GoldBadges, ', S:', fr.SilverBadges, ', B:', fr.BronzeBadges, '; ',
        'Score/View: ', ROUND((fr.QuestionScore::numeric / NULLIF(fr.ViewCount,0)), 4)
    ) AS SummaryInfo
FROM FilteredRanking fr
ORDER BY fr.ParsedTags, fr.QuestionScore DESC, fr.UpVotes DESC;
