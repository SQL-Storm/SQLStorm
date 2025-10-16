-- {"query": "943.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1765} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count,
        COALESCE(p.Score, 0) AS TagExcerptScore,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 1
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT 
        t.Id, 
        t.TagName,
        t.Count, 
        COALESCE(p.Score, 0),
        r.Level + 1
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy r ON r.Id <> t.Id AND t.Count < r.Count
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 1
    WHERE r.Level < 3
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        SUM(vb.BountyAmount) FILTER (WHERE vb.VoteTypeId = 8) AS TotalBountyStarted
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes vb ON vb.UserId = u.Id AND vb.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentNumber
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostWithComments AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        c.CommentSummary,
        c.TotalComments,
        p.CreationDate
    FROM RankedPosts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT
            c.PostId,
            STRING_AGG(DISTINCT COALESCE(NULLIF(TRIM(c.Text), ''), '[no text]'), ' | ' ORDER BY c.CreationDate DESC) AS CommentSummary,
            COUNT(c.Id) AS TotalComments
        FROM Comments c
        GROUP BY c.PostId
    ) c ON c.PostId = p.Id
    WHERE p.ScoreRank <= 10 OR p.RecentNumber <= 5
),
DuplicateLinksAndScores AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lp.Score AS RelatedPostScore,
        p.Score AS PostScore
    FROM PostLinks pl
    INNER JOIN Posts p ON p.Id = pl.PostId
    LEFT JOIN Posts lp ON lp.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3
),
UserBadgeAggregation AS (
    SELECT
        b.UserId,
        b.Name,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId, b.Name
),
FinalOutput AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.BadgesEarned,
        ua.TotalBountyStarted,
        STRING_AGG(DISTINCT rth.TagName || ' (Lvl ' || rth.Level || ')', ', ' ORDER BY rth.Count DESC) AS ImportantTags,
        COALESCE(pwc.TotalComments, 0) AS TotalCommentsOnTopPosts,
        COALESCE(dlas.DuplicateCount, 0) AS DuplicateLinksCount,
        COALESCE(uba.GoldCount, 0) AS GoldBadges,
        COALESCE(uba.SilverCount, 0) AS SilverBadges,
        COALESCE(uba.BronzeCount, 0) AS BronzeBadges
    FROM UserActivity ua
    LEFT JOIN RecursiveTagHierarchy rth ON rth.Level = 1
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            SUM(CommentCount) AS TotalComments
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) pwc ON pwc.OwnerUserId = ua.UserId
    LEFT JOIN (
        SELECT 
            PostId, 
            COUNT(*) AS DuplicateCount
        FROM PostLinks
        WHERE LinkTypeId = 3
        GROUP BY PostId
    ) dlas ON dlas.PostId IN (
        SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId
    )
    LEFT JOIN (
        SELECT 
            uba.UserId, 
            SUM(uba.GoldCount) AS GoldCount, 
            SUM(uba.SilverCount) AS SilverCount, 
            SUM(uba.BronzeCount) AS BronzeCount
        FROM UserBadgeAggregation uba
        GROUP BY uba.UserId
    ) uba ON uba.UserId = ua.UserId
    GROUP BY 
        ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.BadgesEarned,
        ua.TotalBountyStarted, pwc.TotalComments, dlas.DuplicateCount, uba.GoldCount, uba.SilverCount, uba.BronzeCount
)
SELECT 
    fo.UserId, 
    fo.DisplayName, 
    fo.Reputation,
    fo.QuestionsAsked,
    fo.AnswersGiven,
    fo.CommentsMade,
    fo.BadgesEarned,
    fo.TotalBountyStarted,
    fo.ImportantTags,
    fo.TotalCommentsOnTopPosts,
    fo.DuplicateLinksCount,
    fo.GoldBadges,
    fo.SilverBadges,
    fo.BronzeBadges,
    CASE 
        WHEN fo.Reputation > 100000 THEN 'Legendary'
        WHEN fo.Reputation > 50000 THEN 'Epic'
        WHEN fo.Reputation > 10000 THEN 'Veteran'
        WHEN fo.Reputation > 1000 THEN 'Experienced'
        ELSE 'Beginner'
    END AS UserLevel,
    -- Correlated subquery for last asked question title
    (SELECT p.Title
     FROM Posts p
     WHERE p.OwnerUserId = fo.UserId AND p.PostTypeId = 1
     ORDER BY p.CreationDate DESC
     LIMIT 1) AS LastAskedQuestionTitle,
    -- Complex string concatenation with NULL logic and conditional expressions
    CONCAT(
        'User ', COALESCE(fo.DisplayName, '[Unknown]'), ' has ',
        COALESCE(fo.BadgesEarned::text, '0'), ' badges (G:', fo.GoldBadges::text, 
        ', S:', fo.SilverBadges::text, ', B:', fo.BronzeBadges::text, '). ',
        'Asked ', fo.QuestionsAsked::text, ' questions and answered ', fo.AnswersGiven::text, ' posts. ',
        'Tagged with: ', COALESCE(NULLIF(fo.ImportantTags, ''), '[No Tags]'), '.'
    ) AS Summary
FROM FinalOutput fo
ORDER BY fo.Reputation DESC NULLS LAST
LIMIT 100;
